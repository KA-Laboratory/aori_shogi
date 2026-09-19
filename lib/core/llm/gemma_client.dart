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
      final out = await session.getResponse();
      timings.add(DateTime.now().difference(started));
      return out.trim().isEmpty ? null : out.trim();
    } on Object {
      // 生成に失敗しても対局は止めない。呼び出し側が定型文に落とす。
      return null;
    } finally {
      await session?.close();
    }
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
