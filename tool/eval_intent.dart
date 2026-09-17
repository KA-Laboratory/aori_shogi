// 学習ループで生成した約6000文（生成時の意図ラベル付き、ラベルはノイズあり）で分類の一致率を比べる。
// 実行: dart run tool/eval_intent.dart [python/data/learn/candidates/classifier_dataset.jsonl]
import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/dialogue/intent.dart';
import 'package:aori_shogi/core/dialogue/lexicon.dart';

void main(List<String> args) {
  final out = StringBuffer();
  void print(Object? o) => out.writeln(o);
  final path = args.isNotEmpty ? args.first : 'python/data/learn/candidates/classifier_dataset.jsonl';
  final rows = File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  final lex = IntentLexicon.fromJson(File('assets/lexicon/shogi_terms.json').readAsStringSync(),
      File('assets/lexicon/sentiment_ja.json').readAsStringSync());
  final sw = Stopwatch()..start();
  var kw = 0, lx = 0, kwChat = 0, lxChat = 0;
  final confusion = <String, Map<String, int>>{};
  final misses = <String>[];
  for (final r in rows) {
    final text = r['text'] as String;
    final gold = r['kind'] as String;
    final a = classifyKeywords(text, hasPendingOffer: false).kind.name;
    final b = lex.analyze(text, hasPendingOffer: false).intent.kind.name;
    if (a == gold) kw++;
    if (b == gold) lx++;
    if (a == 'chat') kwChat++;
    if (b == 'chat') lxChat++;
    confusion.putIfAbsent(gold, () => {}).update(b, (v) => v + 1, ifAbsent: () => 1);
    if (b != gold && misses.length < 25) misses.add('[$gold→$b] $text');
  }
  final n = rows.length;
  String pct(int x) => '${(x * 100 / n).toStringAsFixed(1)}%';
  print('件数 $n  処理 ${sw.elapsedMilliseconds}ms（1文 ${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(3)}ms）');
  print('キーワード版: 一致 ${pct(kw)} / 雑談扱い（取りこぼし） ${pct(kwChat)}');
  print('辞書版      : 一致 ${pct(lx)} / 雑談扱い（取りこぼし） ${pct(lxChat)}');
  print('辞書版の混同（行=生成意図, 列=判定）:');
  for (final e in confusion.entries) {
    print('  ${e.key.padRight(12)} ${e.value}');
  }
  print('外れ例:');
  misses.forEach(print);
  File('build/eval_intent.txt').writeAsStringSync(out.toString());
  stdout.writeln('wrote build/eval_intent.txt');
}
