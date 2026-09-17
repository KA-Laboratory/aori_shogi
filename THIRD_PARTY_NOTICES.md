# 第三者ソフトウェア

本アプリは GNU General Public License v3（LICENSE）で公開します。以下を含みます。

| 名称 | 用途 | ライセンス | 入手元 |
|---|---|---|---|
| やねうら王 (YaneuraOu) | 思考エンジン（`native/yaneuraou`, submodule） | GPLv3 | https://github.com/yaneurao/YaneuraOu |
| Háo（tanuki- 標準NNUE評価関数 halfkp_256x2-32-32, 2023-05-08） | 評価関数 `nn.bin`（初回起動時にダウンロード。アプリには同梱しない） | GPLv3 | https://github.com/nodchip/tanuki-/releases/tag/tanuki-.halfkp_256x2-32-32.2023-05-08 |
| 日本語評価極性辞書（用言編・名詞編, 東北大学 乾・岡崎研究室） | 自由文の褒め/けなし判定 `assets/lexicon/sentiment_ja.json`（加工） | 出典明記で商用利用可 | https://www.cl.ecei.tohoku.ac.jp/Open_Resources-Japanese_Sentiment_Polarity_Dictionary.html |
| JMdict（EDRDG, jmdict-simplified 3.6.2） | 罵倒・揶揄語、将棋分野語の抽出（`shogi_terms.json` に加工して収録） | CC BY-SA 4.0（帰属表示はアプリ内「このアプリについて」） | https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project |
| Sudachi 同義語辞書（Works Applications） | 将棋用語の表記ゆれ展開 | Apache License 2.0 | https://github.com/WorksApplications/SudachiDict |
| ML-Ask 感情表現辞書（pymlask 同梱） | 感情語・強調語 `assets/lexicon/emotion_ja.json`（加工） | BSD 3-Clause | https://github.com/ikegami-yukino/pymlask |
| Wikipedia 日本語版（Category:将棋の戦法・将棋の囲い・将棋用語） | 戦法・囲い・用語名（`shogi_terms.json` の strategies / shogiContext。tool/fetch_wikipedia_shogi.py） | CC BY-SA 4.0 | https://ja.wikipedia.org/ |
| RealPersonaChat（名古屋大学 東中研究室 ほか） | 雑談発話の誤判定評価のみ（`tool/eval_chat.dart`）。アプリに同梱しない | CC BY-SA 4.0 | https://github.com/nu-dialogue/real-persona-chat |
| 日本語WordNet（NICT, Francis Bond, Takayuki Kuribayashi） | 煽り語・褒め語の言い換え候補（opus-5 が選別して tool/shogi_terms.src.json に追加、src=wordnet+opus） | WordNet 型ライセンス（出典表示） | https://bond-lab.github.io/wnja/ |
| ウィクショナリー日本語版（日本語 慣用句・ことわざ） | 慣用句の見出し・語義（tool/idioms.src.json。意図ラベルは opus-5） | CC BY-SA 4.0 | https://ja.wiktionary.org/ |
| 青空文庫：吉川英治『三国志』 | 軍師口調の見本 python/aori_lab/style/gunshi_quotes.json（研究用プロンプトの味付け） | 著作権保護期間満了 | https://www.aozora.gr.jp/cards/001562/ |
| Tatoeba（日本語文） | 雑談の誤判定評価のみ。同梱しない | CC BY 2.0 FR | https://tatoeba.org/ |
| LLM-jp Toxicity Dataset v2 | 罵倒検出の評価のみ（`tool/eval_toxicity.dart`）。アプリに同梱しない | CC BY 4.0 | https://gitlab.llm-jp.nlp.ec.t.u-tokyo.ac.jp/datasets/llm-jp-toxicity-dataset-v2 |
| 将棋用語辞書（自作） | `assets/lexicon/shogi_terms.json`。用語の選定に将棋用語一覧（Wikipedia, CC BY-SA）を参照 | 本アプリと同じ | tool/shogi_terms.src.json |

日本語評価極性辞書の出典:
- 小林のぞみ, 乾孝司, 松本裕治, 立石健二, 福島俊一. 意見抽出のための評価表現の収集. 自然言語処理, Vol.12, No.3, pp.203-222, 2005.
- 東山昌彦, 乾孝司, 松本裕治. 述語の選択選好性に着目した名詞評価極性の獲得. 言語処理学会第14回年次大会論文集, pp.584-587, 2008.

評価関数の配布: `KA-Laboratory/aori_shogi` の `nnue-assets` ブランチ（main と独立）に、元ファイルを gzip 圧縮した
`nn.bin.gz` と `gpl-3.0.txt` を置く（リポジトリ公開後に取得可能になる）。展開後 64,217,066 バイト、SHA-256
`1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782`（アプリが検証）。
