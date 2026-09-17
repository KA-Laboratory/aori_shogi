// dart run tool/intent_debug.dart  （build/intent_debug_in.txt の各行を分析し build/intent_debug.txt へ）
import 'dart:io';

import 'package:aori_shogi/core/dialogue/lexicon.dart';

void main(List<String> argv) {
  final args = argv.isNotEmpty ? argv : File("build/intent_debug_in.txt").readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final lex = IntentLexicon.fromJson(File('assets/lexicon/shogi_terms.json').readAsStringSync(),
      File('assets/lexicon/sentiment_ja.json').readAsStringSync());
  final out = StringBuffer();
  for (final a in args) {
    final r = lex.analyze(a, hasPendingOffer: false);
    final sc = r.scores.entries.where((e) => e.value > 0).map((e) => '${e.key.name}=${e.value.toStringAsFixed(2)}');
    out.writeln('$a → ${r.intent.kind.name}/${r.intent.request.name} i=${r.intent.intensity.toStringAsFixed(2)} '
        'sent=${r.sentiment} [${sc.join(' ')}] ${r.matched}');
  }
  File('build/intent_debug.txt').writeAsStringSync(out.toString());
}
