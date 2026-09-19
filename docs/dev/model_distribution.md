# モデルの配り方（2026-09-19）

軍師のモデル `.litertlm` は **1.90GB**。小さくできないかを先に潰してから決めた。

## 先に: 小さくできなかった

int4 にすれば 1.04GB（45%減）になり、Play の asset pack 1個の上限 1.5GB にも収まる。
**が、日本語が壊れる。** `dynamic_wi4_afp32` も `dynamic_wi4c_afp32` も同じ壊れ方で、
制御トークンが1語ごとに本文へ割り込む。詳しくは `m3_lora_pipeline.md`。

**1.90GB は動かせない前提で配る。**

配るもの（17g）:

| | |
|---|---|
| サイズ | 1,900,934,064 バイト |
| sha256 | `f89c7f1e3cf5504ae6237c39210fe58b9dfd5bb7c69a995279ba4b310b41a2c2` |
| 元 | Qwen3-1.7B（Apache 2.0）+ 自前の LoRA を統合、int8 量子化 |

## 候補（2026-09-19 に一次資料で確認）

| | 料金 | 制約 |
|---|---|---|
| **Cloudflare R2** | 保存 1.9GB は無料枠（10GB-month）内。**egress 無料** | 実質 ¥0。転送量で課金されない |
| Play Asset Delivery | 無料（Google が配信） | **asset pack 1個 1.5GB 上限 → 2分割必須**。on-demand 合計 30GB |
| Hugging Face | 公開リポジトリは best-effort で無料 | 「数GBを超える分は責任を持って使うこと」と明記。アプリ配信の CDN は想定外 |
| GitHub Releases / raw | 無料 | 1ファイル 2GB 上限（Releases）。raw は 100MB 上限で**論外**。nn.bin(64MB) がこの経路 |

## 決め: Cloudflare R2

理由は3つ。

1. **アプリを直せば済む範囲が一番小さい。** いまの `GunshiModelStore.install` は
   URL からダウンロードする作りなので、`model_catalog.dart` の URL を差し替えるだけ。
2. **転送量で課金されない。** 個人開発でいちばん怖いのは「広まって請求が来る」こと。
   R2 は egress 課金そのものが無いので、この事故が構造的に起きない。
   1万ダウンロード（19TB）でも転送料は 0 円。
3. **iOS でも同じ経路が使える。** PAD は Android 専用で、iOS は On-Demand Resources と
   別の仕組みを書くことになる。

Play Asset Delivery を採らないのは、無料なのに 2分割の実装と `AssetPackManager` 連携、
さらに iOS 側の作り直しが要るから。得（ホスティング代 ¥0）は R2 でも同じ。

Hugging Face は**モデルの置き場所としては併用する**。Qwen3 は Apache 2.0 なので
再配布できるが出所の表示が要る。学習の経緯とライセンスを HF のモデルカードに書き、
**実配信は R2** という分け方にする。

## 手順（未実施）

1. Cloudflare アカウントで R2 バケットを作る（例 `aori-shogi-models`）。
2. `gunshi-qwen3-1_7b-17g.litertlm` としてアップロード。
3. バケットを公開するか、カスタムドメイン（例 `models.ka-laboratory.dev`）を割り当てる。
4. `model_catalog.dart` に軍師モデルの項目を足し、URL・サイズ・sha256 を書く。
5. ダウンロードの検証を入れる（下記）。

## ダウンロードの検証が要る

いまの `install()` は `flutter_gemma` の `fromNetwork()` に任せきりで、
**落ちてきたファイルが正しいか誰も見ていない。** 1.9GB が途中で切れても、
モデルは読み込めてしまい、壊れた日本語を喋る（int4 の試験でその壊れ方は見た）。
サイズ違いを「モデルが悪い」と誤診する事故が起きる。

`NnueStore.download()` に既に正しい型がある: `.part` に落とす → サイズ照合 →
sha256 照合 → rename。モデルも同じにして、検証が通ってから
`GunshiModelStore.installFromFile()` に渡すのがよい。
`installFromFile` は開発用ボタンで既に動いているので、経路は実証済み。

これは URL が決まらないと実地で試せないので、R2 に上げてから着手する。

## nn.bin（64MB）は別の問題

置き場所ではなくライセンスの話。Háo もやねうら王も GPLv3 で、
配布経路を決める前にアプリ全体をどう配るかが決まっていない。分けて考える。
