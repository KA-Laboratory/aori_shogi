import 'package:aori_shogi/core/dialogue/fact_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('実機（S24）で実際に出た、口調は通るが中身が違うセリフ', () {
    test('大差で勝った場面で負けを認める', () {
      expect(
        factViolations('参りました。これも私の勝利でございますよ。', facts: '相手が投了。大差での勝ち。'),
        contains('勝っているのに負けを認めている'),
      );
    });

    test('悪手を最善と言い張る', () {
      expect(
        factViolations('ふむ、これも最善の手でございます。', facts: '直前の手 △７九玉 は悪手（約-2461点損）。私は内心それに気づいている。'),
        contains('悪手を最善と言っている'),
      );
    });
  });

  test('事実にある駒と升目はもちろん通る', () {
    expect(
      factViolations('△６六桂、これが私の読みでございます。',
          facts: '57手目。形勢=優勢（評価値+400）。私の手 △６六桂 は最善。'),
      isEmpty,
    );
  });

  test('相手が口にした升目は言い返してよい', () {
    expect(
      factViolations('△２四歩が危ない、と申されますか。私の計算のうちでございます。',
          facts: '私の直前の手はほぼ最善。相手の煽りは外れ。', playerText: '△２四歩が浮いてるよ'),
      isEmpty,
    );
  });

  test('盤上の他の駒に触れるのは落とさない（事実は直前の一手しか挙げていない）', () {
    // 手書きの527件に駒の検査を当てたら 61件が引っかかったので入れていない。
    // 詳しくは fact_guard.dart のコメント。
    expect(
      factViolations('ふむ、角をそこに置けば、相手の飛車を牽制できるというわけだ。',
          facts: '45手目。形勢=優勢（評価値+300）。私の手 △9七角 は最善。'),
      isEmpty,
    );
    expect(
      factViolations('ふむ、銀を前に出し、守りを固めることで逆転の機を窺うといたしましょう。',
          facts: '12手目。形勢=劣勢（評価値-1200）。私の手 △3四銀 は最善。'),
      isEmpty,
    );
  });

  test('事実にない升目は落とす', () {
    expect(
      factViolations('△２四歩と出れば君は終わりでございます。',
          facts: '57手目。形勢=優勢（評価値+400）。私の手 △６六桂 は最善。'),
      contains('事実にない升目:24'),
    );
  });

  test('雑談は何も見ない', () {
    expect(
      factViolations('犬の散歩は一歩ずつでございますな。', facts: '将棋と関係ない話。形勢=互角。'),
      isEmpty,
    );
  });

  test('事実の側も最善と言っているなら、最善と言ってよい', () {
    // エンジンの最善手を指してなお損をすることはある
    expect(
      factViolations('ふむ…最善の手ではございますが、僅かに損を生んでしまいましたな。',
          facts: '直前の手 △６六桂打（最善手と同じ） は悪手（約-100点損）。私は内心それに気づいている。'),
      isEmpty,
    );
  });

  test('最善の手を最善と言うのは通る', () {
    expect(
      factViolations('ふむ、これぞ最善でございます。',
          facts: '57手目。形勢=優勢（評価値+400）。私の手 △６六桂 は最善。'),
      isEmpty,
    );
  });

  test('負けた場面で勝ちを名乗る', () {
    expect(
      factViolations('私の勝ちでございますな。', facts: '私が投了した。'),
      contains('負けているのに勝ちを名乗っている'),
    );
  });
}
