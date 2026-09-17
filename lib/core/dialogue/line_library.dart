import 'dart:convert';
import 'dart:math' as math;

import '../mind/mind_state.dart';

enum LineTrigger {
  start,
  move,
  tauntHit,
  tauntMiss,
  praised,
  blunderSelf,
  blunderPlayer,
  win,
  lose,
  slip,
  exploitedTrue,
  exploitedFalse,
  praiseFlood,
  praiseSuspicious,
  questionDodge,
  offerPlayerUndo,
  requestRedo,
  proposeDeal,
  proposeDraw,
  offerAccepted,
  offerDeclined,
  requestAccept,
  requestRefuse,
  dealSecret,
  dealBroken,
  redoDone,
  abuse,
  chat,
  smalltalk;

  String get key => switch (this) {
    LineTrigger.start => 'start',
    LineTrigger.move => 'move',
    LineTrigger.tauntHit => 'taunt_hit',
    LineTrigger.tauntMiss => 'taunt_miss',
    LineTrigger.praised => 'praised',
    LineTrigger.blunderSelf => 'blunder_self',
    LineTrigger.blunderPlayer => 'blunder_player',
    LineTrigger.win => 'win',
    LineTrigger.lose => 'lose',
    LineTrigger.slip => 'slip',
    LineTrigger.exploitedTrue => 'exploited_true',
    LineTrigger.exploitedFalse => 'exploited_false',
    LineTrigger.praiseFlood => 'praise_flood',
    LineTrigger.praiseSuspicious => 'praise_suspicious',
    LineTrigger.questionDodge => 'question_dodge',
    LineTrigger.offerPlayerUndo => 'offerPlayerUndo',
    LineTrigger.requestRedo => 'requestRedo',
    LineTrigger.proposeDeal => 'proposeDeal',
    LineTrigger.proposeDraw => 'proposeDraw',
    LineTrigger.offerAccepted => 'offer_accepted',
    LineTrigger.offerDeclined => 'offer_declined',
    LineTrigger.requestAccept => 'request_accept',
    LineTrigger.requestRefuse => 'request_refuse',
    LineTrigger.dealSecret => 'deal_secret',
    LineTrigger.dealBroken => 'deal_broken',
    LineTrigger.redoDone => 'redo_done',
    LineTrigger.abuse => 'abuse',
    LineTrigger.chat => 'chat',
    LineTrigger.smalltalk => 'smalltalk',
  };
}

/// 軍師のテンプレートセリフ（LLM が無いときの代替兼、キャラの芯）。
/// 構造: { mood: { trigger: [line, ...] } }。見つからなければ composed → 汎用文。
class LineLibrary {
  LineLibrary(this._table);

  factory LineLibrary.fromJsonString(String s) {
    final raw = jsonDecode(s) as Map<String, dynamic>;
    return LineLibrary({
      for (final mood in raw.entries)
        mood.key: {
          for (final t in (mood.value as Map<String, dynamic>).entries)
            t.key: [for (final l in t.value as List) l as String],
        },
    });
  }

  static const assetPath = 'assets/lines/gunshi_lines.json';

  final Map<String, Map<String, List<String>>> _table;
  final Map<String, String> _last = {};

  List<String> linesFor(Mood mood, LineTrigger trigger) =>
      _table[mood.name]?[trigger.key] ?? _table[Mood.composed.name]?[trigger.key] ?? const [];

  /// ランダムに1本選ぶ（直前と同じ文は避ける）。{move} {cp} {piece} を置換。
  String pick(Mood mood, LineTrigger trigger, math.Random rng, {Map<String, String> vars = const {}}) {
    final lines = linesFor(mood, trigger);
    if (lines.isEmpty) return '……ふむ。';
    final key = '${mood.name}/${trigger.key}';
    var line = lines[rng.nextInt(lines.length)];
    if (lines.length > 1 && line == _last[key]) {
      line = lines[(lines.indexOf(line) + 1) % lines.length];
    }
    _last[key] = line;
    for (final e in vars.entries) {
      line = line.replaceAll('{${e.key}}', e.value);
    }
    return line;
  }

  Set<String> get moods => _table.keys.toSet();
}
