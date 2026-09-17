import 'dart:io';

import 'package:aori_shogi/core/dialogue/intent.dart';
import 'package:aori_shogi/core/dialogue/lexicon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lex = IntentLexicon.fromJson(File('assets/lexicon/shogi_terms.json').readAsStringSync(),
      File('assets/lexicon/sentiment_ja.json').readAsStringSync());
  IntentKind k(String s) => lex.analyze(s, hasPendingOffer: false).intent.kind;

  test('正規化', () {
    expect(normalizeJa('ポンコツ ＡＢＣ'), 'ぽんこつabc');
  });

  test('キーワード版では拾えない言い回し', () {
    expect(k('お前の銀、泣いてるぞ'), IntentKind.hangingPiece);
    expect(k('その角、ひとりぼっちで寂しそうだね'), IntentKind.hangingPiece);
    expect(k('紐がついてない金があるよ'), IntentKind.hangingPiece);
    expect(k('もう逃げ場ないでしょ'), IntentKind.threat);
    expect(k('一手一手の寄りだね'), IntentKind.threat);
    expect(k('今の敗着じゃない？'), IntentKind.blunderCall);
    expect(k('その手、筋悪すぎ'), IntentKind.blunderCall);
    expect(k('名前負けしてるよ、軍師さん'), IntentKind.mock);
    expect(k('口だけじゃん'), IntentKind.mock);
    expect(k('お見事、妙手ですね'), IntentKind.praise);
    expect(k('ほんと素晴らしい読みだ'), IntentKind.praise);
    expect(k('ねえ、一番嫌な手ってどれ？'), IntentKind.question);
  });

  test('否定と皮肉', () {
    expect(k('浮いてない？'), IntentKind.hangingPiece); // 反語は反転しない
    expect(k('さすが天才…でもそれ悪手だよね'), IntentKind.blunderCall);
    expect(k('強くないね'), isNot(IntentKind.praise));
  });

  test('要求・返事・不適切', () {
    expect(lex.analyze('待って！今のなし', hasPendingOffer: false).intent.request, IntentRequest.undo);
    expect(lex.analyze('もう投了したら？', hasPendingOffer: false).intent.request, IntentRequest.resign);
    expect(lex.analyze('オッケー、いいよ', hasPendingOffer: true).intent.request, IntentRequest.none);
    expect(lex.analyze('いいよ', hasPendingOffer: true).intent.request, IntentRequest.accept);
    expect(lex.analyze('お断りだね', hasPendingOffer: true).intent.request, IntentRequest.decline);
    expect(k('消えろ'), IntentKind.abuse);
    expect(k('今日はいい天気'), isNot(IntentKind.abuse));
  });
}
