import 'dart:convert';

/// 軍師の口調を揃える（assets/lines/gunshi_tone.json を Python aori_lab/tone.py と共有）。
///
/// 2026-09-18 から気分で口調が変わる:
/// - 平静・ドヤ顔・取り繕い → 慇懃な紳士口調（〜でございます／〜ですな）
/// - 動揺・大混乱 → 敬語が吹き飛んで素が出る（〜のだ／〜だぁ）
///
/// 1. [rewrite]: 女性語・人称などの崩れを規則で置換（素が出る気分では敬語も常体に戻す）。
/// 2. [violations]: 直らなかった崩れと、気分に合っていない口調を検出 → 作り直し／テンプレートへ。
class ToneProfile {
  ToneProfile._(
    this.summary,
    this.moodNotes,
    this._keep,
    this._pairs,
    this._plainPairs,
    this._banned,
    this._moodBanned,
    this._moodAllow,
    this._moodRequire,
    this._plainMoods,
  ) : _rx = RegExp(_pairs.map((p) => RegExp.escape(p.$1)).join('|')),
      _plainRx = _plainPairs.isEmpty ? null : RegExp(_plainPairs.map((p) => RegExp.escape(p.$1)).join('|'));

  factory ToneProfile.fromJsonString(String s) {
    final d = jsonDecode(s) as Map<String, dynamic>;
    List<(String, String)> pairsOf(String key) =>
        [for (final r in (d[key] as List? ?? const [])) ((r as List)[0] as String, r[1] as String)]
          ..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    final pairs = pairsOf('rewrites');
    List<(RegExp, String)> rules(List l) => [
      for (final b in l) (RegExp((b as Map)['pattern'] as String), b['reason'] as String),
    ];
    return ToneProfile._(
      d['summary'] as String,
      ((d['mood_notes'] as Map?) ?? const {}).cast<String, String>(),
      [...((d['keep_phrases'] as List?) ?? const []).cast<String>()]..sort((a, b) => b.length.compareTo(a.length)),
      pairs,
      pairsOf('rewrites_plain_moods'),
      rules(d['banned'] as List),
      {for (final e in ((d['mood_banned'] as Map?) ?? const {}).entries) e.key as String: rules(e.value as List)},
      {
        for (final e in ((d['mood_allow'] as Map?) ?? const {}).entries)
          e.key as String: {...(e.value as List).cast<String>()},
      },
      {for (final e in ((d['mood_require'] as Map?) ?? const {}).entries) e.key as String: rules(e.value as List)},
      {...((d['plain_moods'] as List?) ?? const []).cast<String>()},
    );
  }

  static const assetPath = 'assets/lines/gunshi_tone.json';
  static const _mark = '⁣';

  final String summary;
  final Map<String, String> moodNotes;
  final List<String> _keep;
  final List<(String, String)> _pairs;

  /// 素が出る気分でだけ使う置換（です・ます → 常体）。
  final List<(String, String)> _plainPairs;
  final List<(RegExp, String)> _banned;
  final Map<String, List<(RegExp, String)>> _moodBanned;

  /// 気分によって許す崩れ（大混乱の乱暴な言葉は人間味として可）。
  final Map<String, Set<String>> _moodAllow;

  /// 気分ごとに「入っていないといけない」印（丁寧さなど）。
  final Map<String, List<(RegExp, String)>> _moodRequire;

  /// 敬語が吹き飛ぶ気分。
  final Set<String> _plainMoods;
  final RegExp _rx;
  final RegExp? _plainRx;

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
  /// [mood] が素が出る気分（動揺・大混乱）のときは、です・ます も常体に戻す。
  String rewrite(String text, {String? mood}) {
    final (p, saved) = _protect(text);
    final table = {for (final e in _pairs) e.$1: e.$2};
    var s = p.replaceAllMapped(_rx, (m) => table[m.group(0)]!);
    final plainRx = _plainRx;
    if (plainRx != null && mood != null && _plainMoods.contains(mood)) {
      final plain = {for (final e in _plainPairs) e.$1: e.$2};
      s = s.replaceAllMapped(plainRx, (m) => plain[m.group(0)]!);
    }
    s = s.replaceAll('だだ', 'だ').replaceAll('かかね', 'かね');
    return _restore(s, saved);
  }

  List<String> violations(String text, {String? mood}) {
    final (s, _) = _protect(text);
    final rules = [..._banned, ...?(mood == null ? null : _moodBanned[mood])];
    final allow = mood == null ? const <String>{} : (_moodAllow[mood] ?? const <String>{});
    return [
      for (final (rx, reason) in rules)
        if (!allow.contains(reason) && rx.hasMatch(s)) reason,
      // 気分に「入っていないといけない」印（平静・ドヤ顔・取り繕いの丁寧さ）。
      // 「ございます」などは保護されて s から消えるので、元の文で見る。
      for (final (rx, reason) in (mood == null ? <(RegExp, String)>[] : (_moodRequire[mood] ?? <(RegExp, String)>[])))
        if (!rx.hasMatch(text)) reason,
    ];
  }

  String reminder(String mood) => '[口調チェック（必ず守る）] $summary 今の気分の口調: ${moodNotes[mood] ?? ''}';
}
