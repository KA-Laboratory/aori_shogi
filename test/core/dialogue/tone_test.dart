import 'dart:io';

import 'package:aori_shogi/core/dialogue/tone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tone = ToneProfile.fromJsonString(File('assets/lines/gunshi_tone.json').readAsStringSync());

  test('よくある崩れを規則で直す（Python 版と同じ結果）', () {
    expect(tone.rewrite('犬の散歩は大変よね〜。どの種類だった？'), '犬の散歩は大変だろう。どの種類だった？');
    expect(tone.rewrite('あなたの手、そう思いますね。', mood: 'rattled'), '君の手、そう思うね。');
    expect(tone.rewrite('よろしくお願いします。私は強いぞ'), 'よろしくお願いします。私は強いぞ');
  });

  test('素が出る気分でだけ、です・ますを常体に戻す', () {
    // 動揺・大混乱は敬語が吹き飛ぶ
    expect(tone.rewrite('雨が嫌いなんですか？', mood: 'rattled'), '雨が嫌いなのかね？');
    // 平静・ドヤ顔・取り繕いは慇懃なまま
    expect(tone.rewrite('雨が嫌いなんですか？', mood: 'composed'), '雨が嫌いなんですか？');
  });

  test('気分に合わない口調を見つける', () {
    expect(tone.violations('ふむ、当然でございますな。', mood: 'composed'), isEmpty);
    expect(tone.violations('ふむ、当然なのだ。', mood: 'composed'), contains(startsWith('丁寧さが足りない')));
    expect(tone.violations('……いや、計算どおりなのだ。', mood: 'rattled'), isEmpty);
    expect(tone.violations('計算どおりでございます。', mood: 'rattled'), contains('です・ます調'));
  });

  test('直せない崩れは検出する', () {
    expect(tone.violations('行きましたか？', mood: 'rattled'), contains('です・ます調'));
    expect(tone.violations('そやな、じゃねえか'), containsAll(['関西弁', '乱暴な口調']));
    expect(tone.violations('一手待ってやろうか？', mood: 'rattled'), isEmpty);
    expect(tone.violations('勝利の方程式が見えるわ！'), isEmpty);
    expect(tone.violations('へぇ〜そうなんだ', mood: 'composed'), isNotEmpty);
    // 大混乱の乱暴な言葉は人間味として許す（です・ますは不可のまま）
    expect(tone.violations('うるせえ！ ちげえって言ってんだろ', mood: 'meltdown'), isEmpty);
    expect(tone.violations('うるせえ！', mood: 'composed'), contains('乱暴な口調'));
    // 慇懃な紳士口調は平静・ドヤ顔・取り繕いでは崩れ扱いしない
    expect(tone.violations('ハッハッハ！ 喜んで頂戴いたしますよ。', mood: 'smug'), isEmpty);
  });

  test('テンプレートセリフ自体は口調規則を守っている', () {
    final lines = File('assets/lines/gunshi_lines.json').readAsStringSync();
    expect(RegExp('わよ|かしら|あなた|でしょう').hasMatch(lines), isFalse);
  });
}
