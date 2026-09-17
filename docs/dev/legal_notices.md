# 公開時に必要な表示（2026-09-18 整理）

アプリ内の「このアプリについて」（lib/features/about/about_page.dart）に出す。実際の公開前にここを見て抜けを確認する。

## 1. 本体（GPLv3）

やねうら王と Háo を組み込むため、アプリ全体を GPLv3 で公開する。GPLv3 が求めるのは次の3つ。

- ライセンスの明示（済）
- **同一版のソースの入手先を示す**（未対応だった → 画面に URL を出す）。ストア版と同じコミットに tag を打ち、その tag を指す URL にする。
- 改変した場合はその旨を書く（やねうら王は FFI から呼ぶだけで未改変。ブリッジ `native/bridge` は自作でこのリポジトリに含む）

## 2. 評価関数（Háo / tanuki-）

GPLv3。配布物（Release の nn.bin）に `gpl-3.0.txt` を同梱する。アプリ内の表示は済。

## 3. 端末内LLM（M3で入れるとき）

Gemma を使う場合、Gemma Terms of Use が次を求める（https://ai.google.dev/gemma/terms）。

- 利用規約と Prohibited Use Policy を利用者に提示する（画面にリンクを出す）
- 「Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms」という Notice を配布物に含める
- 改変したモデル（LoRAをマージしたもの）には改変した旨を明記する
- 利用制限を自分の利用規約に引き継ぐ

→ モデルを入れる版から about_page に「端末内AI」の節を足す。今は入っていないので書かない。

## 4. 辞書・資料

JMdict（CC BY-SA 4.0）、Wikipedia / ウィクショナリー（CC BY-SA 4.0）、日本語WordNet、Sudachi 同義語辞書（Apache 2.0）、ML-Ask（BSD 3-Clause）、日本語評価極性辞書（東北大）、青空文庫。表示は済。
CC BY-SA の派生物（lexicon.dart に取り込んだ語）は同じライセンスで提供する必要がある。本体が GPLv3 なので、辞書部分は CC BY-SA 4.0 であることを表示で分けて書いてある。

## 5. nn.bin（64MB）の配布経路

今の状態: `nnue-assets` ブランチに置いてあるが、**リポジトリが非公開なので raw.githubusercontent から落とせない**。開発中は adb で配置している（docs/dev/nnue.md）。

公開時の選択肢:

| 案 | 中身 | 良い点 | 悪い点 |
|---|---|---|---|
| (a) このリポジトリを公開し、Releases に置く | GPLv3 のソース公開義務も同時に満たす | 一番素直。追加の場所が要らない | 公開の時期を選べない（今すぐ公開になる） |
| (b) 資産用の公開リポジトリを別に作る（例 KA-Laboratory/aori_shogi_assets）の Releases | 本体は公開前でも DL 経路が作れる | ソース公開は別途必要（公開時にこのリポジトリを公開） | 置き場所が2つに分かれる |
| (c) ka-laboratory.github.io（GitHub Pages）に置く | 既にあるサイトを使える | 1ファイル100MB制限内（64MB）で収まる | リポジトリ容量を食う。帯域の保証はない |

**おすすめは (b) → 公開時に (a) に寄せる**。アプリ側の DL 先は `nnue_store.dart` の URL を差し替えるだけで済む。
