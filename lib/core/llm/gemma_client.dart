/// flutter_gemma を [LlmClient] として差し込む。**flutter_gemma に触れるのはこのファイルだけ**。
///
/// 方針（docs/dev/m3_llm_integration.md）:
/// - モデルが無くてもゲームは成立する。無ければ [ready] が false になり、呼び出し側は定型文に落ちる。
/// - 1回のセリフごとに session を作って捨てる。軍師は毎ターン気分が変わるので履歴を持たない方が素直で、
///   端末のメモリも抱え込まない。
library;

import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../dialogue/speaker.dart';
import 'model_catalog.dart';
import 'single_flight.dart';

ModelType _modelType(LlmFamily f) => switch (f) {
  LlmFamily.gemmaIt => ModelType.gemmaIt,
  LlmFamily.gemma4 => ModelType.gemma4,
  LlmFamily.qwen3 => ModelType.qwen3,
};

/// モデルの導入・削除と、いま使える状態かどうか。UI から呼ぶ。
class GunshiModelStore {
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    _initialized = true;
  }

  /// 端末にモデルがあり、使う設定になっているか。
  Future<bool> isReady() async {
    await _ensureInit();
    return FlutterGemma.hasActiveModel();
  }

  /// ダウンロードして有効にする。進捗は 0..100。すでに入っていれば有効化するだけ。
  Future<void> install(LlmModelSpec spec, {void Function(int percent)? onProgress}) async {
    await _ensureInit();
    await FlutterGemma.installModel(modelType: _modelType(spec.family), fileType: ModelFileType.litertlm)
        .fromNetwork(spec.url, foreground: true)
        .withProgress((p) => onProgress?.call(p))
        .install();
  }

  /// 端末に置いたファイルから入れる（開発用: adb で push した .litertlm を試すため）。
  Future<void> installFromFile(String path, LlmFamily family) async {
    await _ensureInit();
    await FlutterGemma.installModel(modelType: _modelType(family), fileType: ModelFileType.litertlm)
        .fromFile(path)
        .install();
  }

  /// 入っているモデルを消す（容量を戻す）。
  Future<void> removeAll() async {
    await _ensureInit();
    for (final id in await FlutterGemma.listInstalledModels()) {
      await FlutterGemma.uninstallModel(id);
    }
    await FlutterGemma.clearActiveInferenceIdentity();
  }

  Future<List<String>> installedIds() async {
    await _ensureInit();
    return FlutterGemma.listInstalledModels();
  }
}

/// 端末内LLMの口。[LlmSpeaker] から呼ばれる。
class GemmaLlmClient implements LlmClient {
  GemmaLlmClient({
    this.maxTokens = 1024,
    this.maxOutputTokens = 120,
    this.temperature = 0.6,
    this.topP = 0.9,
    this.topK = 40,
  });

  /// 文脈の広さ。`.litertlm` は 1024 未満だと確保に失敗する。
  final int maxTokens;

  /// 生成の長さ。セリフは1〜3文なのでごく短くてよい。
  final int maxOutputTokens;
  /// 0.9 だと日本語が壊れることが追加学習後の試し打ちで分かったので 0.6。
  /// （docs/dev/m3_lora_pipeline.md「試し打ちで分かったこと」）
  final double temperature;
  final double topP;
  final int topK;

  InferenceModel? _model;
  var _seed = 1;

  /// 生成を1つずつに絞る門。同時に2つ走らせると LiteRT-LM が落ちる（[SingleFlight]）。
  final _gate = SingleFlight();

  /// 重なって断った回数（開発用の目安）。
  int get droppedWhileBusy => _gate.dropped;

  /// 直近の生成にかかった時間（受け入れ条件 p95 < 6秒 の計測用）。
  final List<Duration> timings = [];

  @override
  bool get ready => _model != null;

  /// モデルを読み込む。導入されていなければ何もしない（[ready] は false のまま）。
  Future<void> load() async {
    if (_model != null) return;
    await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    if (!FlutterGemma.hasActiveModel()) return;
    _model = await FlutterGemma.getActiveModel(maxTokens: maxTokens, preferredBackend: PreferredBackend.gpu);
  }

  @override
  Future<String?> generate({required String system, required String user}) async {
    final model = _model;
    if (model == null) return null;
    if (!_gate.tryEnter()) return null;
    final started = DateTime.now();
    InferenceModelSession? session;
    try {
      session = await model.createSession(
        temperature: temperature,
        randomSeed: _seed++,
        topK: topK,
        topP: topP,
        systemInstruction: system,
        maxOutputTokens: maxOutputTokens,
      );
      await session.addQueryChunk(Message.text(text: user, isUser: true));
      final out = dropRepeats(stripControlTokens(await session.getResponse()));
      timings.add(DateTime.now().difference(started));
      return out.isEmpty ? null : out;
    } on Object {
      // 生成に失敗しても対局は止めない。呼び出し側が定型文に落とす。
      return null;
    } finally {
      await session?.close();
      _gate.leave();
    }
  }

  /// 制御トークンを落とす。
  ///
  /// 実機（S24）で確かめたところ、Qwen3 の思考チャネルの印が本文に混ざって
  /// `<|channel>thought <channel|> 君、形勢がどうだ？` のような形で返ってくる。
  /// 最後の制御トークンより後ろだけを本文として使う。
  static String stripControlTokens(String s) {
    final tokens = RegExp(r'<\|?[A-Za-z_]+\|?>').allMatches(s).toList();
    if (tokens.isEmpty) return s.trim();
    final tail = s.substring(tokens.last.end).trim();
    // 制御トークンが末尾にあって本文が残らない場合は、印だけ落とす
    return tail.isEmpty ? s.replaceAll(RegExp(r'<\|?[A-Za-z_]+\|?>'), '').trim() : tail;
  }

  /// 同じ文の繰り返しを落とす。
  ///
  /// LiteRT-LM のサンプラーが持つのは top_k / top_p / temperature / seed だけで、
  /// repetition penalty に当たる設定が無い（flutter_gemma_litertlm の
  /// native/litert_lm/include/engine.h, LiteRtLmSamplerParams）。実機では
  /// 「ふむ…空いていても私の歩は最善でございる。」が丸ごと2回並ぶことがあったので、
  /// 生成側で抑えられない分をここで機械的に落とす。
  ///
  /// 末尾が途中で切れた断片で、しかもそれが前に出た文の言い出しと同じ場合も落とす
  /// （maxOutputTokens で繰り返しの2周目が切られた形）。
  static String dropRepeats(String s) {
    final parts = RegExp(
      r'[^。！？!?]*[。！？!?]+|[^。！？!?]+',
    ).allMatches(s).map((m) => m.group(0)!).toList();
    final kept = <String>[];
    final seen = <String>{};
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final key = part.replaceAll(RegExp(r'[\s、。！？!?…・ー]'), '');
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      final unfinished = !RegExp(r'[。！？!?]$').hasMatch(part.trimRight());
      if (i == parts.length - 1 && unfinished && key.length >= 4 && seen.any((k) => k.startsWith(key))) {
        continue;
      }
      seen.add(key);
      kept.add(part.trim());
    }
    return kept.isEmpty ? s.trim() : kept.join();
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
