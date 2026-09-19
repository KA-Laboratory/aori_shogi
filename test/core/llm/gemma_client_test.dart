import 'package:aori_shogi/core/llm/gemma_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('思考チャネルの印を落として本文だけ取り出す（S24 の実機で出た形）', () {
    expect(
      GemmaLlmClient.stripControlTokens('<|channel>thought <channel|> 君、形勢がどうだ？ 金を狙うのだ、私の計算が正しいのだ！'),
      '君、形勢がどうだ？ 金を狙うのだ、私の計算が正しいのだ！',
    );
    expect(
      GemmaLlmClient.stripControlTokens('<|channel>final<channel|>ふむ、計算どおりでございます。'),
      'ふむ、計算どおりでございます。',
    );
  });

  test('印が無ければそのまま', () {
    expect(GemmaLlmClient.stripControlTokens('  ふむ、当然でございますな。 '), 'ふむ、当然でございますな。');
  });

  test('本文が残らないときは印だけ落とす', () {
    expect(GemmaLlmClient.stripControlTokens('ふむ、見事だ。<|im_end|>'), 'ふむ、見事だ。');
  });

  test('丸ごと同じ文の繰り返しを落とす（S24 の実機で出た形）', () {
    expect(
      GemmaLlmClient.dropRepeats('ふむ…空いていても私の歩は最善でございる。ふむ…空いていても私の歩は最善でございる。'),
      'ふむ…空いていても私の歩は最善でございる。',
    );
  });

  test('途中で切れた2周目も落とす', () {
    expect(
      GemmaLlmClient.dropRepeats('計算どおりでございます。まだ余裕がございますな。計算どおりでご'),
      '計算どおりでございます。まだ余裕がございますな。',
    );
  });

  test('違う文は残す', () {
    const s = 'ふむ、読めておったわ。だが次はどうかな？';
    expect(GemmaLlmClient.dropRepeats(s), s);
  });

  test('句点が無い1文はそのまま', () {
    expect(GemmaLlmClient.dropRepeats('な、なんだと'), 'な、なんだと');
  });

  test('短い掛け声が二度出るのは繰り返しとして落とす', () {
    expect(GemmaLlmClient.dropRepeats('ぐわー！ぐわー！やられた！'), 'ぐわー！やられた！');
  });
}
