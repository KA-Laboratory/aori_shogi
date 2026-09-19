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
}
