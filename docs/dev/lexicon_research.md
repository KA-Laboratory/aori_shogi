# 辞書・語彙資源の調査（2026-09-17）

目的: 煽り将棋の自由文分類（lib/core/dialogue/lexicon.dart）と軍師の反応を強化できる、日本語の辞書・データを探す。
前提: アプリは GPLv3 で公開。端末に同梱する場合は容量（数MBまで）と、GPLv3 と両立するライセンスが必要。

## 現在使っているもの
| 資源 | 用途 | ライセンス |
|---|---|---|
| 自作 将棋用語辞書（240語） | 煽りの種類の判定 | 本アプリ |
| 日本語評価極性辞書（東北大, 約1万語） | 褒め/けなし | 出典明記で商用可 |

## 候補の評価
凡例: ◎ 同梱して使える / ○ 開発時の加工・評価に使える / △ 条件確認が必要 / × 不向き

| 資源 | 中身 | ライセンス | 同梱 | 使い道 |
|---|---|---|---|---|
| **JMdict**（EDRDG） | 日本語‐英語辞書 約20万見出し。語ごとに `derog`（侮蔑）`vulg`（下品）`sl`（俗語）`net-sl`（ネット俗語）`col`（口語）`joc`（おどけ）などのタグ、読み、表記ゆれ | CC BY-SA 4.0（アプリはAbout画面等でクレジット表示・定期更新が条件。GPLv3と一方向互換） | ◎（必要な語だけ抽出すれば数百KB） | 不適切語リストの拡充（derog/vulg）、からかい語（joc/sl）、ネット俗語、読みによる表記ゆれ吸収 |
| **Sudachi 同義語辞書**（ワークス徳島） | 同義語グループのCSV。代表語・略語・表記ゆれ・誤用のフラグ、分野情報 | Apache-2.0 | ◎（関係する語の抽出） | 将棋用語・褒め・けなし語の言い換え展開（例: 「下手」「へた」「ヘタ」、略語） |
| **ML-Ask 感情語辞書**（pymlask 同梱） | 10感情（喜・怒・哀・怖・恥・好・厭・昂・安・驚）の語、強調語（「めっちゃ」「超」等）、顔文字、感嘆表現 | BSD-3-Clause | ◎ | 軍師への発言の感情の種類と強さ（intensity）、顔文字・「ｗ」「！」の扱い |
| **LLM-jp Toxicity Dataset v2**（NII LLM-jp） | Common Crawl 由来の文書 3,847件に有害/非有害と種別（猥褻・差別・暴力・違法など）を人手付与 | CC BY（商用可） | ○（文書データ。語彙抽出と評価用） | 不適切判定の誤検出/見逃しの評価 |
| **日本語版 Wiktionary（kaikki.org の JSON）** | 日本語約19.5万語義。定義文、慣用句、派生語 | CC BY-SA / GFDL | ○ | 将棋用語・慣用句（「筋が悪い」「王手をかける」）の意味と例文の収集 |
| **日本語WordNet**（NICT/Bond） | 9.4万語、概念の上位下位・類義 | BSD風（クレジット要） | ○ | 類義語展開（ただし約5%誤りとの注記） |
| **ゲーム解説コーパス**（京大 森研） | プロの将棋解説文 約74万文、局面(SFEN)付き、将棋用語の固有表現タグ | 要問い合わせ | △ | 将棋の言い回し（評価表現・戦法名・手筋）の大量抽出。問い合わせる価値あり |
| **WRIME**（阪大ほか） | SNS投稿 3.5万件に8感情の強度・極性 | CC BY-NC-ND 4.0（非商用・改変不可） | × | 同梱・学習済みモデル配布は不可。社内の精度評価のみ |
| japanese-toxic-dataset（inspection-ai） | 有害表現スキーマとサブセット | 明記なし | △ | ライセンス確認まで使わない |
| JIWC 感情表現辞書（NAIST） | 7感情、約1,000〜1,700語 | 明記なし | △ | ML-Ask で代替可 |
| chiVe（単語ベクトル） | 数十万〜数百万語×300次元 | Apache-2.0 | ×（数百MB〜GB） | 開発時に「新しい言い回し→近い辞書語」を提案させる用途なら ○ |
| mecab-ipadic-NEologd | 新語入り形態素辞書 | Apache-2.0 | ×（大きい・更新停止） | — |

## おすすめ（優先順）
1. **JMdict のタグで不適切語・俗語・からかい語を拡充**: 侮蔑・下品タグの語を「不適切」、おどけ・俗語の一部を「からかい」に。誤爆しやすい短い語は除外リストで管理。
2. **Sudachi 同義語辞書で自作辞書の表記ゆれ・言い換えを自動展開**: 240語 → 数倍に。
3. **ML-Ask の強調語・顔文字・感嘆表現で「強さ」を推定**: 煽りの効き目（intensity）に反映。
4. **LLM-jp Toxicity Dataset で不適切判定を評価**（アプリには入れない）。
5. **京大 ゲーム解説コーパスの利用を問い合わせ**: 将棋の生きた言い回しの最大の供給源。
- WRIME は非商用・改変不可のため採用しない。

いずれも tool/build_lexicon.py に取り込み処理を足し、assets/lexicon の JSON（合計数百KB以内）に焼き込む。出典は THIRD_PARTY_NOTICES とアプリの「このアプリについて」に表示する（JMdict の条件）。

## 出典
- JMdict ライセンス: https://www.edrdg.org/edrdg/licence.html / タグ方針: https://www.edrdg.org/wiki/Editorial_policy.html
- Sudachi 同義語辞書: https://github.com/WorksApplications/SudachiDict/blob/develop/docs/synonyms.md
- pymlask（ML-Ask）: https://github.com/ikegami-yukino/pymlask
- LLM-jp Toxicity Dataset v2: https://llm-jp.nii.ac.jp/news/post-551/
- kaikki.org 日本語版Wiktionary: https://kaikki.org/jawiktionary/index.html
- 日本語WordNet: https://bond-lab.github.io/wnja/jpn/downloads.html
- ゲーム解説コーパス: http://www.lsta.media.kyoto-u.ac.jp/resource/data/game/
- WRIME: https://github.com/ids-cv/wrime
- japanese-toxic-dataset: https://github.com/inspection-ai/japanese-toxic-dataset
- JIWC: https://github.com/sociocom/JIWC-Dictionary
- chiVe: https://github.com/WorksApplications/chiVe
