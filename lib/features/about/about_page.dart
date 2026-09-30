import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 「このアプリについて」: 利用データ・ソフトウェアの出典表示（JMdict などの帰属表示義務を満たす）。
class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  /// この版のソースの入手先（ストア公開時は公開したタグの URL にする）。
  static const sourceUrl = 'https://github.com/KA-Laboratory/aori_shogi';

  static const credits = <(String, String)>[
    ('やねうら王 (YaneuraOu)', '思考エンジン。GPLv3。https://github.com/yaneurao/YaneuraOu'),
    ('Háo（tanuki- NNUE評価関数）', '評価関数。GPLv3。https://github.com/nodchip/tanuki-'),
    (
      'JMdict',
      'This application uses the JMdict dictionary files. These files are the property of the '
          'Electronic Dictionary Research and Development Group, and are used in conformance with the '
          "Group's licence (CC BY-SA 4.0). https://www.edrdg.org/edrdg/licence.html\n"
          '（加工: jmdict-simplified 版から罵倒・揶揄語と将棋分野語を抽出）',
    ),
    (
      'Wikipedia 日本語版',
      '将棋の戦法・囲い・用語の記事名を用語辞書に利用。CC BY-SA 4.0。https://ja.wikipedia.org/',
    ),
    (
      '日本語WordNet',
      'Japanese Wordnet © 2009-2011 NICT, 2012-2015 Francis Bond and 2016-2024 Francis Bond, Takayuki Kuribayashi。煽り語・褒め語の言い換え選定に利用。https://bond-lab.github.io/wnja/',
    ),
    (
      'ウィクショナリー日本語版',
      '慣用句・ことわざの見出しと語義を参照。CC BY-SA 4.0。https://ja.wiktionary.org/',
    ),
    (
      '青空文庫',
      '吉川英治『三国志』（著作権保護期間満了）の言い回しを軍師の口調づくりの参考に利用。https://www.aozora.gr.jp/',
    ),
    (
      'Sudachi 同義語辞書',
      'Works Applications。Apache License 2.0。https://github.com/WorksApplications/SudachiDict',
    ),
    (
      'ML-Ask 感情表現辞書',
      '中村明「感情表現辞典」に基づく語彙（Ptaszynski ほか）。BSD 3-Clause。https://github.com/ikegami-yukino/pymlask',
    ),
    (
      '日本語評価極性辞書',
      '東北大学 乾・岡崎研究室。小林ほか (2005) 自然言語処理 12(3)、東山ほか (2008) 言語処理学会第14回年次大会。',
    ),
  ];

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  late final Future<PackageInfo?> _packageInfo;
  @override
  void initState() {
    super.initState();
    _packageInfo = _readPackageInfo();
  }

  Future<PackageInfo?> _readPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSupport() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(AboutAppPage.sourceUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      /* Keep the selectable fallback available. */
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブラウザを開けませんでした。下のURLをコピーして開いてください。')),
      );
    }
  }

  Future<void> _showAssetLicense(String title, String path) async {
    String text;
    try {
      text = await rootBundle.loadString(path);
    } catch (_) {
      text =
          'ライセンス文を読み込めませんでした。アプリのソースに同梱した通知をご確認ください。\n${AboutAppPage.sourceUrl}';
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('このアプリについて')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('煽り将棋', style: Theme.of(context).textTheme.headlineSmall),
                FutureBuilder<PackageInfo?>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Text('バージョンを確認しています');
                    }
                    final info = snapshot.data;
                    return Text(
                      info == null
                          ? 'バージョン情報を取得できませんでした'
                          : 'バージョン ${info.version}（ビルド ${info.buildNumber}）',
                    );
                  },
                ),
                heading('プライバシー'),
                const Text('会話処理と軍師の記憶は端末内で扱います。言葉のモデルが未導入の場合は定型文で話します。'),
                const SizedBox(height: 8),
                const Text(
                  'モデル・評価関数の取得時と、外部リンクを開くときは通信します。軍師の記憶とモデルは、それぞれの管理画面から削除できます。',
                ),
                const SizedBox(height: 8),
                const Text(
                  '現在局の会話・棋譜は対局画面で確認できます。対局履歴は自動保存されません。必要な棋譜はKIFコピーを利用してください。',
                ),
                heading('サポート情報・ソース'),
                const Text('サポート情報はソースリポジトリで確認できます。外部ブラウザを開きます。対局中は時計が進みます。'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openSupport,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('サポート情報を開く'),
                ),
                const SelectableText(AboutAppPage.sourceUrl),
                heading('ライセンスと出典'),
                const Text(
                  'このプロジェクトのソースライセンスは GNU General Public License v3 です。',
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  'ソースの入手先: ${AboutAppPage.sourceUrl}\n'
                  '思考エンジン「やねうら王」は改変せず FFI から呼び出しています。'
                  '呼び出し部分（native/bridge, packages/yaneuraou_ffi）は本アプリの一部で、同じライセンスです。',
                ),
                heading('同梱素材'),
                const Text(
                  '日本語UI書体: Noto Sans JP。SIL Open Font License 1.1。フォントの著作権表示とライセンス文を同梱しています。',
                ),
                TextButton(
                  onPressed: () => _showAssetLicense(
                    'Noto Sans JP ライセンス',
                    'assets/fonts/OFL.txt',
                  ),
                  child: const Text('フォントのライセンス全文'),
                ),
                const Text('効果音: このプロジェクト向けの手続き的合成音です。出典・権利表記は同梱通知をご確認ください。'),
                TextButton(
                  onPressed: () => _showAssetLicense(
                    '効果音の出典・ライセンス',
                    'assets/audio/ASSET-LICENSES.md',
                  ),
                  child: const Text('効果音の出典・ライセンス'),
                ),
                const Text(
                  '軍師の表情画像: このプロジェクト向けにAI生成した画像を使用しています。第三者配布のCC0素材として扱うものではありません。',
                ),
                const SizedBox(height: 16),
                for (final (name, body) in AboutAppPage.credits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SelectableText(
                          body,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: '煽り将棋',
                  ),
                  child: const Text('パッケージのライセンス'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
