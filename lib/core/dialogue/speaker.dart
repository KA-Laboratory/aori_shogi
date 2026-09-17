/// 軍師のセリフをどこから出すか。テンプレートと端末内LLMを差し替えられるようにする。
///
/// - [TemplateSpeaker]: assets/lines/gunshi_lines.json の定型文（LLM無しでも遊べる芯）。
/// - [LlmSpeaker]: 端末内LLM（M3で flutter_gemma を [LlmClient] として差す）。
///   口調は Python 版と同じ手順で守る: 生成 → 規則で書き換え → 崩れが残れば作り直し → それでも駄目ならテンプレート。
library;

import 'dart:math' as math;

import '../mind/mind_state.dart';
import 'line_library.dart';
import 'player_memory.dart';
import 'tone.dart';

/// セリフ1回分の材料。
class SpeechRequest {
  const SpeechRequest({
    required this.trigger,
    required this.mood,
    required this.facts,
    this.playerText = '',
    this.instruction = '',
    this.vars = const {},
    this.memory,
    this.recentLines = const [],
  });

  final LineTrigger trigger;
  final Mood mood;

  /// 盤面の事実（手数・形勢・直前の手など）。ここに無いことは言わせない。
  final String facts;
  final String playerText;

  /// 今言うことの指示（例: 煽りが図星で効いた）。
  final String instruction;
  final Map<String, String> vars;
  final PlayerMemory? memory;

  /// 直近の自分のセリフ（言い回しの繰り返しを避けるため）。
  final List<String> recentLines;
}

abstract class GunshiSpeaker {
  /// セリフを返す。出せなければ null（呼び出し側はテンプレートに落とす）。
  Future<String?> speak(SpeechRequest req);
}

/// 定型文から選ぶ。
class TemplateSpeaker implements GunshiSpeaker {
  TemplateSpeaker(this.lines, {math.Random? rng}) : _rng = rng ?? math.Random();

  final LineLibrary lines;
  final math.Random _rng;

  @override
  Future<String?> speak(SpeechRequest req) async => lines.pick(req.mood, req.trigger, _rng, vars: req.vars);
}

/// 端末内LLMの口。flutter_gemma でも別の実装でも、この形だけ満たせばよい。
abstract class LlmClient {
  /// 使える状態か（モデルが端末にあるか）。
  bool get ready;

  /// 1回分の生成。返すのは軍師のセリフ1〜3文だけ。出せなければ null。
  Future<String?> generate({required String system, required String user});
}

/// LLMに喋らせ、口調は規則で担保する。
class LlmSpeaker implements GunshiSpeaker {
  LlmSpeaker({required this.client, required this.tone, required this.lines, this.maxAttempts = 2, this.maxChars = 90});

  final LlmClient client;
  final ToneProfile tone;
  final LineLibrary lines;

  /// 崩れたときに作り直す回数（端末では遅いので少なめ）。
  final int maxAttempts;
  final int maxChars;

  @override
  Future<String?> speak(SpeechRequest req) async {
    if (!client.ready) return null;
    final system = systemPrompt;
    final user = buildUserPrompt(req, tone, lines);
    for (var i = 0; i < maxAttempts; i++) {
      final raw = (await client.generate(system: system, user: user))?.trim();
      if (raw == null || raw.isEmpty) continue;
      final line = tone.rewrite(_oneLine(raw));
      if (line.length > maxChars) continue;
      if (tone.violations(line, mood: req.mood.name).isNotEmpty) continue;
      return line;
    }
    return null;
  }

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s*\n+\s*'), ' ').replaceAll(RegExp(r'^[「『]|[」』]$'), '');

  /// Python 版 docs/dev/finetune_data_prompt.md のシステムプロンプトと同じ骨。
  static const systemPrompt =
      'あなたは将棋アプリ「煽り将棋」の登場人物「自称・天才軍師」本人だ。'
      '自信満々だがどこか抜けている愛嬌のあるポンコツとして、プレイヤーと将棋を指している人として喋る。'
      '一人称は「私」、相手は「君」。セリフは日本語で1〜3文、90字以内。'
      'ト書き・括弧書き・絵文字・説明は書かない。将棋の内容は「事実」に書かれたことだけを根拠にし、'
      '事実にない指し手・駒・評価値を作らない。差別・容姿・人格攻撃・下品な言葉は書かない。'
      'セリフだけを返す。';

  /// 事実・相手の発言・記憶・口調の念押しを1つの文にまとめる。
  static String buildUserPrompt(SpeechRequest req, ToneProfile tone, LineLibrary lines) {
    final parts = <String>['[事実] ${req.facts}'];
    if (req.playerText.isNotEmpty) parts.add('[相手の発言] ${req.playerText}');
    final memory = req.memory;
    if (memory != null && memory.facts.isNotEmpty) parts.add(memory.promptBlock(req.playerText));
    if (req.recentLines.isNotEmpty) {
      parts.add('[私の最近のセリフ（言い回し・書き出しを繰り返さない）]\n${req.recentLines.take(4).join('\n')}');
    }
    final examples = lines.linesFor(req.mood, req.trigger).take(4);
    if (examples.isNotEmpty) {
      parts.add('[今の気分の口調の見本（そのまま使わず、今の状況に合わせて新しく言う）]\n${examples.join('\n')}');
    }
    if (req.instruction.isNotEmpty) parts.add('[今言うこと] ${req.instruction}');
    // 長い対話で口調が薄れるので、毎回いちばん最後に口調を念押しする
    parts.add(tone.reminder(req.mood.name));
    return parts.join('\n\n');
  }
}
