import 'dart:convert';

/// 軍師の口調を揃える（assets/lines/gunshi_tone.json を Python aori_lab/tone.py と共有）。
/// 1. [rewrite]: です・ます、女性語、人称などのよくある崩れを規則で置換（決定的）。
/// 2. [violations]: 置換で直らなかった崩れを検出 → 作り直し／テンプレートへ。
class ToneProfile {
  ToneProfile._(this.summary, this.moodNotes, this._keep, this._pairs, this._banned, this._moodBanned, this._moodAllow)
    : _rx = RegExp(_pairs.map((p) => RegExp.escape(p.$1)).join('|'));

  factory ToneProfile.fromJsonString(String s) {
    final d = jsonDecode(s) as Map<String, dynamic>;
    final pairs = [for (final r in d['rewrites'] as List) ((r as List)[0] as String, r[1] as String)]
      ..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    List<(RegExp, String)> rules(List l) => [
      for (final b in l) (RegExp((b as Map)['pattern'] as String), b['reason'] as String),
    ];
    return ToneProfile._(
      d['summary'] as String,
      ((d['mood_notes'] as Map?) ?? const {}).cast<String, String>(),
      [...((d['keep_phrases'] as List?) ?? const []).cast<String>()]..sort((a, b) => b.length.compareTo(a.length)),
      pairs,
      rules(d['banned'] as List),
      {for (final e in ((d['mood_banned'] as Map?) ?? const {}).entries) e.key as String: rules(e.value as List)},
      {
        for (final e in ((d['mood_allow'] as Map?) ?? const {}).entries)
          e.key as String: {...(e.value as List).cast<String>()},
      },
    );
  }

  static const assetPath = 'assets/lines/gunshi_tone.json';
  static const _mark = '⁣';

  final String summary;
  final Map<String, String> moodNotes;
  final List<String> _keep;
  final List<(String, String)> _pairs;
  final List<(RegExp, String)> _banned;
  final Map<String, List<(RegExp, String)>> _moodBanned;

  /// 気分によって許す崩れ（大混乱の乱暴な言葉は人間味として可）。
  final Map<String, Set<String>> _moodAllow;
  final RegExp _rx;

  (String, List<String>) _protect(String s) {
    final saved = <String>[];
    for (final k in _keep) {
      while (s.contains(k)) {
        saved.add(k);
        s = s.replaceFirst(k, '$_mark${saved.length - 1}$_mark');
      }
    }
    return (s, saved);
  }

  String _restore(String s, List<String> saved) =>
      s.replaceAllMapped(RegExp('$_mark(\\d+)$_mark'), (m) => saved[int.parse(m.group(1)!)]);

  /// 長い語から1パスで置換（置換結果は再置換しない）。
  String rewrite(String text) {
    final (p, saved) = _protect(text);
    final table = {for (final e in _pairs) e.$1: e.$2};
    final s = p.replaceAllMapped(_rx, (m) => table[m.group(0)]!).replaceAll('だだ', 'だ').replaceAll('かかね', 'かね');
    return _restore(s, saved);
  }

  List<String> violations(String text, {String? mood}) {
    final (s, _) = _protect(text);
    final rules = [..._banned, ...?(mood == null ? null : _moodBanned[mood])];
    final allow = mood == null ? const <String>{} : (_moodAllow[mood] ?? const <String>{});
    return [
      for (final (rx, reason) in rules)
        if (!allow.contains(reason) && rx.hasMatch(s)) reason,
    ];
  }

  String reminder(String mood) => '[口調チェック（必ず守る）] $summary 今の気分の口調: ${moodNotes[mood] ?? ''}';
}
