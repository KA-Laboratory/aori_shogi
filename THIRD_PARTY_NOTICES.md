# 第三者ソフトウェア

本アプリは GNU General Public License v3（LICENSE）で公開します。以下を含みます。

| 名称 | 用途 | ライセンス | 入手元 |
|---|---|---|---|
| やねうら王 (YaneuraOu) | 思考エンジン（`native/yaneuraou`, submodule） | GPLv3 | https://github.com/yaneurao/YaneuraOu |
| Háo（tanuki- 標準NNUE評価関数 halfkp_256x2-32-32, 2023-05-08） | 評価関数 `nn.bin`（初回起動時にダウンロード。アプリには同梱しない） | GPLv3 | https://github.com/nodchip/tanuki-/releases/tag/tanuki-.halfkp_256x2-32-32.2023-05-08 |
| 日本語評価極性辞書（用言編・名詞編, 東北大学 乾・岡崎研究室） | 自由文の褒め/けなし判定 `assets/lexicon/sentiment_ja.json`（加工） | 出典明記で商用利用可 | https://www.cl.ecei.tohoku.ac.jp/Open_Resources-Japanese_Sentiment_Polarity_Dictionary.html |
| 将棋用語辞書（自作） | `assets/lexicon/shogi_terms.json`。用語の選定に将棋用語一覧（Wikipedia, CC BY-SA）を参照 | 本アプリと同じ | tool/shogi_terms.src.json |

日本語評価極性辞書の出典:
- 小林のぞみ, 乾孝司, 松本裕治, 立石健二, 福島俊一. 意見抽出のための評価表現の収集. 自然言語処理, Vol.12, No.3, pp.203-222, 2005.
- 東山昌彦, 乾孝司, 松本裕治. 述語の選択選好性に着目した名詞評価極性の獲得. 言語処理学会第14回年次大会論文集, pp.584-587, 2008.

評価関数の配布: `KA-Laboratory/aori_shogi` の `nnue-assets` ブランチ（main と独立）に、元ファイルを gzip 圧縮した
`nn.bin.gz` と `gpl-3.0.txt` を置く（リポジトリ公開後に取得可能になる）。展開後 64,217,066 バイト、SHA-256
`1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782`（アプリが検証）。
