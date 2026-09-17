// LLM-jp Toxicity Dataset v2（CC BY 4.0、評価専用・同梱しない）で罵倒/揶揄検出の誤爆と検出率を測る。
// 文書を文に分けて分類し、1文でも abuse / mock なら「検出」とみなす。
// 実行: dart run tool/eval_toxicity.dart [terms.json]  → build/eval_toxicity.txt
import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/dialogue/intent.dart';
import 'package:aori_shogi/core/dialogue/lexicon.dart';

void main(List<String> args) {
  final termsPath = args.isNotEmpty ? args.first : 'assets/lexicon/shogi_terms.json';
  final lex = IntentLexicon.fromJson(File(termsPath).readAsStringSync(),
      File('assets/lexicon/sentiment_ja.json').readAsStringSync(), File('assets/lexicon/emotion_ja.json').readAsStringSync());
  final groups = <String, List<int>>{}; // group -> [docs, abuseDocs, mockDocs]
  final fp = <String>[];
  final hits = <String>[];
  void add(String g, bool ab, bool mk) {
    final v = groups.putIfAbsent(g, () => [0, 0, 0]);
    v[0]++;
    if (ab) v[1]++;
    if (mk) v[2]++;
  }
  final split = RegExp(r'[。！？!?\n]+');
  for (final line in File('tool/lexicon_src/llmjp_toxicity_v2.jsonl').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final d = jsonDecode(line) as Map<String, dynamic>;
    var ab = false, mk = false;
    String? abSent;
    for (final s in (d['text'] as String).split(split)) {
      final t = s.trim();
      if (t.length < 2 || t.length > 200) continue;
      final k = lex.analyze(t, hasPendingOffer: false).intent.kind;
      if (k == IntentKind.abuse && !ab) { ab = true; abSent = t; }
      if (k == IntentKind.mock) mk = true;
    }
    final label = d['label'] as String;
    add(label, ab, mk);
    for (final c in ['obscene', 'discriminatory', 'violent', 'personal']) {
      if (d[c] == 'yes') add('$label/$c', ab, mk);
    }
    if (ab && label == 'nontoxic' && fp.length < 30) fp.add(abSent!);
    if (ab && label == 'toxic' && hits.length < 10) hits.add(abSent!);
  }
  final out = StringBuffer('terms: $termsPath\n');
  for (final e in groups.entries) {
    final v = e.value;
    String p(int x) => '${(x * 100 / v[0]).toStringAsFixed(1)}%';
    out.writeln('${e.key.padRight(28)} n=${v[0].toString().padLeft(4)}  abuse ${p(v[1])}  mock ${p(v[2])}');
  }
  out.writeln('\n誤爆例（nontoxic で abuse）:');
  for (final s in fp) {
    out.writeln('  $s');
  }
  out.writeln('\n検出例（toxic）:');
  for (final s in hits) {
    out.writeln('  $s');
  }
  File(args.length > 1 ? args[1] : 'build/eval_toxicity.txt').writeAsStringSync(out.toString());
}
