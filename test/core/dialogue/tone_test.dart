import 'dart:io';

import 'package:aori_shogi/core/dialogue/line_library.dart';
import 'package:aori_shogi/core/dialogue/tone.dart';
import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tone = ToneProfile.fromJsonString(File('assets/lines/gunshi_tone.json').readAsStringSync());

  test('よくある崩れを規則で直す（Python 版と同じ結果）', () {
    expect(tone.rewrite('犬の散歩は大変よね〜。どの種類だった？'), '犬の散歩は大変だろう。どの種類だった？');
    expect(tone.rewrite('あなたの手、そう思いますね。', mood: 'meltdown'), '君の手、そう思うね。');
    expect(tone.rewrite('よろしくお願いします。私は強いぞ'), 'よろしくお願いします。私は強いぞ');
  });

  test('「ございます」の崩れた活用を直す（実機で出た形）', () {
    // 「ございます」と「〜いる」が混線したもの。学習データには一度も無く、
    // モデルが作った形なので、出力側で直す。
    expect(tone.rewrite('天気のいい日は最高の過ごし方でございいるよ！'), '天気のいい日は最高の過ごし方でございますよ！');
    expect(tone.rewrite('空いていても私の歩は最善でございる。'), '空いていても私の歩は最善でございます。');
  });

  test('素が出る気分でだけ、です・ますを常体に戻す', () {
    // 大混乱は敬語が吹き飛ぶ
    expect(tone.rewrite('雨が嫌いなんですか？', mood: 'meltdown'), '雨が嫌いなのかね？');
    // 平静・ドヤ顔・取り繕いは慇懃なまま
    expect(tone.rewrite('雨が嫌いなんですか？', mood: 'composed'), '雨が嫌いなんですか？');
    // 動揺は敬語が崩れかけている段階。丁寧なままでも直さない
    expect(tone.rewrite('雨が嫌いなんですか？', mood: 'rattled'), '雨が嫌いなんですか？');
  });

  test('気分に合わない口調を見つける', () {
    expect(tone.violations('ふむ、当然でございますな。', mood: 'composed'), isEmpty);
    expect(tone.violations('ふむ、当然なのだ。', mood: 'composed'), contains(startsWith('丁寧さが足りない')));
    expect(tone.violations('……いや、計算どおりなのだ。', mood: 'rattled'), isEmpty);
    // 動揺は丁寧でも常体でもよい（敬語が崩れかけている段階）
    expect(tone.violations('計算どおりでございます。', mood: 'rattled'), isEmpty);
    expect(tone.violations('計算どおりでございます。', mood: 'meltdown'), contains('です・ます調'));
  });

  test('直せない崩れは検出する', () {
    expect(tone.violations('行きましたか？', mood: 'meltdown'), contains('です・ます調'));
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

  test('テンプレートセリフ自体が気分ごとの口調規則を守っている', () {
    final lib = LineLibrary.fromJsonString(File('assets/lines/gunshi_lines.json').readAsStringSync());
    final bad = <String>[];
    for (final mood in Mood.values) {
      for (final trigger in LineTrigger.values) {
        for (final line in lib.linesFor(mood, trigger)) {
          final raw = line.replaceAll('{move}', '△７六歩').replaceAll('{fact}', '次は△３四歩');
          // 実際の表示と同じく、気分に合わせて整えてから判定する
          final text = tone.rewrite(raw, mood: mood.name);
          final v = tone.violations(text, mood: mood.name);
          if (v.isNotEmpty) bad.add('${mood.name}/${trigger.key} ${v.join(",")}: $line');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
