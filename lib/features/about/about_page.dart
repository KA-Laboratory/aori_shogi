import 'package:flutter/material.dart';

/// 「このアプリについて」: 利用データ・ソフトウェアの出典表示（JMdict などの帰属表示義務を満たす）。
class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  static const credits = <(String, String)>[
    ('やねうら王 (YaneuraOu)', '思考エンジン。GPLv3。https://github.com/yaneurao/YaneuraOu'),
    ('Háo（tanuki- NNUE評価関数）', '評価関数。GPLv3。https://github.com/nodchip/tanuki-'),
    (
      'JMdict',
      'This application uses the JMdict dictionary files. These files are the property of the '
          'Electronic Dictionary Research and Development Group, and are used in conformance with the '
          "Group's licence (CC BY-SA 4.0). https://www.edrdg.org/edrdg/licence.html\n"
          '（加工: jmdict-simplified 版から罵倒・揶揄語と将棋分野語を抽出）'
    ),
    ('Sudachi 同義語辞書', 'Works Applications。Apache License 2.0。https://github.com/WorksApplications/SudachiDict'),
    ('ML-Ask 感情表現辞書', '中村明「感情表現辞典」に基づく語彙（Ptaszynski ほか）。BSD 3-Clause。https://github.com/ikegami-yukino/pymlask'),
    (
      '日本語評価極性辞書',
      '東北大学 乾・岡崎研究室。小林ほか (2005) 自然言語処理 12(3)、東山ほか (2008) 言語処理学会第14回年次大会。'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('このアプリについて')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('煽り将棋は GNU General Public License v3 で公開しています。'),
          const SizedBox(height: 16),
          for (final (name, body) in credits)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                SelectableText(body, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          OutlinedButton(
            onPressed: () => showLicensePage(context: context, applicationName: '煽り将棋'),
            child: const Text('パッケージのライセンス'),
          ),
        ],
      ),
    );
  }
}
