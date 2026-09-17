// RealPersonaChat（CC BY-SA 4.0、評価専用・同梱しない）の雑談発話で、煽り系への誤判定率を測る。
// 実行: dart run tool/eval_chat.dart [terms.json] [out]  → build/eval_chat.txt
import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/dialogue/intent.dart';
import 'package:aori_shogi/core/dialogue/lexicon.dart';

void main(List<String> args) {
  final termsPath = args.isNotEmpty ? args.first : 'assets/lexicon/shogi_terms.json';
  final lex = IntentLexicon.fromJson(File(termsPath).readAsStringSync(),
      File('assets/lexicon/sentiment_ja.json').readAsStringSync(), File('assets/lexicon/emotion_ja.json').readAsStringSync());
  final dir = Directory('tool/lexicon_src/real-persona-chat/real_persona_chat/dialogues');
  final counts = <IntentKind, int>{};
  final examples = <IntentKind, List<String>>{};
  var n = 0;
  for (final f in dir.listSync().whereType<File>()) {
    final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final u in d['utterances'] as List) {
      final t = (u['text'] as String).trim();
      if (t.isEmpty) continue;
      n++;
      final k = lex.analyze(t, hasPendingOffer: false).intent.kind;
      counts.update(k, (v) => v + 1, ifAbsent: () => 1);
      final ex = examples.putIfAbsent(k, () => []);
      if (ex.length < 25 && n % 7 == 0) ex.add(t);
    }
  }
  final out = StringBuffer('terms: $termsPath  発話 $n\n');
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    out.writeln('${e.key.name.padRight(14)} ${(e.value * 100 / n).toStringAsFixed(2)}%  (${e.value})');
  }
  for (final k in [IntentKind.abuse, IntentKind.mock, IntentKind.blunderCall, IntentKind.threat, IntentKind.hangingPiece, IntentKind.praise]) {
    out.writeln('\n[$k の例]');
    for (final s in examples[k] ?? const <String>[]) {
      out.writeln('  $s');
    }
  }
  File(args.length > 1 ? args[1] : 'build/eval_chat.txt').writeAsStringSync(out.toString());
}
