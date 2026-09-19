# M3: キャラ追加学習（LoRA）から `.litertlm` までの道筋

調査日 2026-09-19（opus-5）。**実際に `litert-torch` を入れて `--help` とソースを読んで確かめた**ので、
ここに書いてある引数と対応モデルは推測ではない。学習データの作り方は docs/dev/finetune_writing_guide.md。

## 結論: 追加学習したモデルを `.litertlm` にできる

`litert-torch export_hf` は **ローカルの safetensors ディレクトリ**を受け取れる。
つまり「PC で LoRA 学習 → ベースにマージ → そのフォルダを渡す」で端末用のファイルが作れる。

```
litert-torch export_hf <MODEL> <OUTPUT_DIR> [flags]
  MODEL        HuggingFace のリポジトリ名、または safetensors ディレクトリのパス
  -b, --bundle_litert_lm   .litertlm にまとめる（これを付けないと .tflite のまま）
  -q, --quantization_recipe 量子化の指定（下表）
  --externalize_embedder    埋め込み表を外に出す（チュートリアルはこれを付けている）
  --prefill_lengths / --cache_length  文脈の長さ（アプリは maxTokens=1024）
```

対応している系列（`litert_torch/generative/export_hf/model_ext/` の中身）:
**gemma3 / gemma3n / gemma4 / gemma4_unified / lfm2 / qwen3 / qwen3_5**（ほかに ASR・TTS 系）。
候補にしている Gemma 3 1B・Gemma 4 E2B・Qwen3 0.6B はいずれも入っている。

量子化のレシピ名（ai_edge_quantizer より）:

| 種類 | 名前 |
|---|---|
| 動的 | `dynamic_wi8_afp32`, `dynamic_wi4_afp32` |
| 重みのみ | `weight_only_wi8_afp32`, `weight_only_wi4_afp32` |
| 静的 | `static_wi8_ai8`, `static_wi8_ai16` |
| LiteRT-LM 向け | `gemma4_mixed48`, `gemma4_mixed48_hr`, `gemma4_mixed48_b32`, `gemma4_mixed48_b64` |
| 変換ツール内蔵 | `dynamic_wi8_emb4_afp32`（埋め込み4bit＋全結合8bit） |

読み方: `dynamic`=動的量子化、`wi[N]`=重みNビット、`c`=チャンネル単位 / `b[M]`=Mブロック単位、
`afp32`=活性はfp32、`hr`=アダマール回転あり。

## 環境（ここが一番の注意点）

- **`litert-torch` は Linux のみ**（Python 3.10 以上、3.11 推奨）。賢太郎さんの PC は Windows なので
  **WSL2 で回す**ことになる。RTX 3070 Ti は WSL2 から使えるので、学習も変換も WSL2 に寄せるのが素直。
- 入れ方:
  ```
  uv tool install litert-torch-nightly   # 変換（torch 2.14 / transformers 5.17 が入る。数GB）
  uv tool install litert-lm              # PC 上で .litertlm を試しに動かす
  ```
- 変換は CPU/メモリを食う。1B 級なら普通のPCで通る見込み。E2B は要検証。

## 手順

1. **データ**（済み: 530件）
   ```
   cd python
   uv run python tools/make_sft.py     # → data/finetune_gen_edit/sft_{train,eval}.jsonl
   ```
   1行 = `{"messages":[system, user, assistant]}`。**アプリが実際に投げるプロンプトと同じ形**にしてある
   （`lib/core/dialogue/speaker.dart` の `LlmSpeaker.systemPrompt` と、user 末尾の口調の念押し）。
   ここがずれると、学習しても本番で効かない。

2. **LoRA 学習**（WSL2、未実施）
   ベースは Gemma 3 1B（`google/gemma-3-1b-it`）から。peft + trl の SFTTrainer で、
   r=16 / alpha=32 / lr=1e-4 / 3〜5 epoch あたりから。478件と小さいので過学習に注意し、
   eval 52件の loss を見ながら止める。

3. **マージ**: `peft` の `merge_and_unload()` でベースに焼き込み、safetensors で保存する。
   （LoRA アダプタを実行時に差す道は flutter_gemma / LiteRT-LM のどちらにも無い → docs/dev/m3_llm_integration.md）

4. **変換**（**2026-09-19 に素の Qwen3 0.6B で実際に通した**）
   ```
   litert-torch export_hf /path/to/merged-gunshi out/litertlm \
       --bundle_litert_lm --quantization_recipe dynamic_wi8_emb4_afp32 \
       --externalize_embedder --cache_length 1024 --prefill_lengths 512 \
       --experimental_lightweight_conversion True
   ```
   - **`--experimental_lightweight_conversion True` は必須に近い。** 付けないと MLIR に落とす途中で
     メモリを使い切って落ちる（2コア8GBの環境で、無言で死んだ）。付ければ **2分10秒・661MB** で
     `model.litertlm` ができた。`--prefill_lengths` は 128 でも 512 でも同じ時間・同じ大きさだった。
     アプリのプロンプトは system＋事実＋口調の念押しで数百トークンになるので 512 にしておく。
   - 量子化の効き: 埋め込みは 7.6倍小さくなった（0.6B が 661MB）。

5. **端末に入れる**: できた `.litertlm` を配布先（未決: nn.bin と同じ経路）に置き、
   `lib/core/llm/model_catalog.dart` に軍師モデルとして足す。開発中は adb で直接置いてもよい。

6. **評価**: `python/tools/eval_persona.py`（崩れ・テンプレート落ち・速さ）と `tools/ab_compare.py`
   （素のモデル vs 追加学習ずみを伏せて比べる）。受け入れは実機で p95 < 6秒。

## 変換をどこで回すか（2026-09-19 に実測して結論が変わった）

`litert-torch` は Linux のみ。当初は「学習は Windows・変換は opus-5 側の Linux（2コア8GB）」で
進める判断だったが、**メモリが足りない**ことが分かった。

| モデル | 8GB の環境で変換 | 備考 |
|---|---|---|
| Qwen3 0.6B | **通る**（2分10秒・661MB） | `--experimental_lightweight_conversion True` が必要 |
| Qwen3 1.7B | **通らない** | 重みの読み込み中（46%付近）でメモリを使い切って落ちる |

そして試し打ちの結果、**0.6B では日本語が持たず 1.7B 以上が要る**。つまり
**変換にはメモリの大きい Linux が要る** → 賢太郎さんの PC（物理メモリ 32GB）に **WSL2 を入れるのが本筋**。

```
# 管理者の PowerShell で
wsl --install
# 再起動のあと
uv tool install litert-torch-nightly
```

WSL2 なら学習（CUDA も使える）も変換も1台で完結し、数GBのモデルを運ぶ必要もなくなる。

### WSL2 で実際に通した（2026-09-19）

賢太郎さんが `wsl --install` を実行。Ubuntu 26.04.1 LTS、**24コア / 15GB / 955GB**。
`uv` と `litert-torch-nightly`（＋PCで試し撃ちする `litert-lm`）を入れ、**1.7B の変換が 110秒で成功**。

| | 素の Qwen3 0.6B | 追加学習した Qwen3 1.7B |
|---|---|---|
| 変換した場所 | クラウド 2コア8GB | **WSL2 24コア15GB** |
| 時間 | 2分10秒 | **1分50秒** |
| `.litertlm` | 661MB | **1.90GB** |

できたファイルは `python/out/litertlm17/model.litertlm`。

手順は `tool/wsl/` にスクリプトで置いた（Windows から `tool\wsl_run.cmd <名前>` で走る）。

| スクリプト | すること |
|---|---|
| `check.sh` | WSL の素性（CPU・メモリ・ディスク・入っている道具） |
| `setup.sh` | uv と litert-torch-nightly / litert-lm を入れる（1回だけ） |
| `convert.sh` | マージ済みモデルを WSL 側にコピー → `.litertlm` に変換 → `python/out/litertlm17/` に置く |
| `lm_try.sh` | できた `.litertlm` を PC 上で喋らせてみる（**CPU なので非常に遅い**。速さの判定には使えない） |

注意: `/mnt/c` は遅いので、`convert.sh` はモデルを WSL のファイルシステム（`~/gunshi-convert`）に
コピーしてから変換する。

## 試し打ちで分かったこと（2026-09-19、実測）

530件のデータで実際に2本学習した（Windows の RTX 3070 Ti、bf16 + LoRA、4 epoch）。

| ベース | 時間 | eval_loss（1→4 epoch） | トークン一致 | 日本語 |
|---|---|---|---|---|
| Qwen3 0.6B | 7分 | 0.63 → 0.30 | 94.1% | **持たない**。「空くでございます」「満天の笑い場」 |
| Qwen3 1.7B | 11.6分 | 0.77 → **0.264** | 94.4% | だいぶ良い。ときどき妙な言い回しが残る |

- **口調はちゃんと学習できる。** 気分ごとに「〜でございます」「〜のだ」が出るようになり、
  口調チェックに引っかかるのは 10件中 1件だけ（1.7B）。データと作り方は効いている。
- **生成温度が効く。** 同じモデルでも temperature 0.9 では日本語が崩れ、**0.6 に下げると文がほぼ整う**。
  アプリ側（`GemmaLlmClient`）の既定も 0.6 / top_p 0.9 に変えた。
- 0.6B は素の日本語能力が足りない。**1.7B 以上を使う。**

## 日本語をもう一段上げる、3つの手（2026-09-19 に実測）

実機の試し撃ちで残っていた2つの傷 ——(a) 妙な語彙（「いたずこむ不器用さ」「空くでございる」）、
(b) 同じ文の丸ごと繰り返し —— に、3方向から当たって分かったこと。

### 1. 繰り返しは生成側では止められない（→ Dart で落とした）

`flutter_gemma_litertlm` の `native/litert_lm/include/engine.h` にある `LiteRtLmSamplerParams` は
`type / top_k / top_p / temperature / seed` の5つだけ。**repetition penalty に当たる設定は無い。**
サンプラーの種類も TopK / TopP / Greedy の3つで、繰り返しを罰する仕組みが入っていない。

なので `GemmaLlmClient.dropRepeats` で後始末する。同じ文の2度目を捨て、末尾が途中で切れた
断片が前の文の言い出しと同じ場合も捨てる。Python 側（`train/sample.py` の `repeats`）も
同じ見方で数を出すので、学習の良し悪しを同じ物差しで比べられる。

### 2. LoRA を弱めるのは逆効果だった

「学習が強すぎて崩れた活用を作っているのでは」と考えて、弱め（rank 8 / lr 5e-5 / 3 epoch）を
同じデータで学習し、同じお題・同じ seed（temp 0.6 / top_p 0.9）で並べた。

| | eval_loss | 口調の崩れ | 繰り返し | 中身 |
|---|---|---|---|---|
| 現行 rank16 / lr1e-4 / 4ep | 0.264 | 1/12 | 0/12 | セリフだけを返す |
| 弱め rank8 / lr5e-5 / 3ep | 0.940 | 3/12 | 1/12 | **ト書きが出る**「（指し手を突き出す）」「『……』」 |

弱めると、素の Qwen3 の「場面を describe する」癖が戻ってくる。
**セリフだけを返させているのは、この強さの学習そのもの。** 強さは下げない。

### 3. ベースの大型化は、この機体では学習側で詰まる

RTX 3070 Ti は VRAM 8GB。1.7B の bf16 + LoRA は通るが、4B 級は重みだけで 8GB を超える。
bitsandbytes を使わない方針なので、**4B 以上のベースはこの機体では学習できない。**
大型化をやるなら 4bit 量子化を入れるか、クラウドの GPU を借りる話になる。

### 残るのはデータ量。まず事実の食い違いを1件見つけて直した

`tools/probe_stance.py` で、事実の「形勢=」と「評価値」が食い違う行を探したら 2件出た。

    move-composed-0011  形勢=互角（評価値-1200） -> 本来 劣勢
    move-composed-0013  形勢=互角（評価値-1400） -> 本来 劣勢

どちらも1周目のモデル生成由来（`cmp_qwen3_8b`）。そして **-1400 の方は、実機で
「互角に持ち込むとは」という出力が出たお題そのもの**だった。数字の読み方を1件で
壊していたことになる。機械的に落として 528件にし、`build_edit_set.flags()` に
`形勢と評価値が食い違い` の検査を足したので、以後は取り込み時点で弾かれる。

### 事実を全部アプリの型に書き直した（2026-09-19、賢太郎さんの判断）

残していた「判断が要る分」を、落とさずに**事実の方を書き直す**ことにした。
そこから `tools/probe_appshape.py` で場面ごとにアプリの型と総当たりしたら、
最初に見つけた分は氷山の一角だった。**全角の「形勢＝」と誤字（形拡・形応）**のせいで、
それまでの `形勢=` を見る検査を素通りしていた行がまだあった。

直した内訳（セリフには一度も触れていない）:

| 直した所 | 件数 | 何が違ったか |
|---|---|---|
| 形勢の言い方（機械的な言い換え） | 28 | 有利→優勢、微妙→互角、形勢=+500→優勢（評価値+500） |
| 形勢と評価値の食い違い・「評価値±N」 | 36 | 符号が ± のまま／言葉と数字が噛み合わない |
| 褒められた回数 | 34 | アプリは `praised` を praiseStreak<3 のときしか出さないのに「8回目」がある。雛形の「（4回以上）」が残っている |
| 全角＝・誤字・形勢の抜け | 21 | `abuse` 14件に形勢が無い、`question_dodge` 6件が「形勢＝不利だが逆転の可能性あり」 |
| 落とした | 3 | 事実と評価値が食い違う2件、セリフが評価値の数字を引用していて型に直すと宙に浮く1件 |

結果、**照合できる9場面 218件すべてがアプリの型と一致**（`probe_appshape.py`）。
`build_edit_set.flags()` に `事実がアプリの型と違う` を足したので、以後は取り込みで弾かれる。

アプリ側も1つ直した。`praised` が回数を送っていなかったので
`形勢=X。相手に褒められた（N回目）。`、`praiseFlood/praiseSuspicious` を
`相手にN回続けて褒められた。` にした（`praiseStreak` はもともと持っていた）。
**事実の文面はアプリと学習データで同じでなければならない。** 片方だけ直すと元に戻る。

### プロンプトから文法用語を外した（17g）

17d と 17f の試し打ちで、軍師が「貴方の一手が常体でございますよ」「私は常体語でございます」と
喋っていた。**「常体」は学習データに一度も出てこない。** 口調プロファイルの `summary` と
`mood_notes.rattled`（毎回プロンプト末尾に付く念押し）に書いてあった語を、そのまま
オウム返ししていた。12件中1〜2件に出ていたので、プロンプト側を言い換えた
（「丁寧でも常体でもよい」→「丁寧なままでも、崩れてもよい」）。

プロンプトを変えると学習時と推論時がずれるので、`sft_*.jsonl` を作り直してから学習し直す。

### 学習し直した結果

| | 件数 | eval_loss | 口調の崩れ | 繰り返し |
|---|---|---|---|---|
| 17a（元） | 530 | 0.2636 | 1/12 | 0/12 |
| 17c（食い違い除去） | 528 | 0.2564 | 0/12 | 0/12 |
| 17d（形勢の言い方も揃えた） | 528 | 0.2564 | 0/12 | 0/12 |
| 17f（事実を全部アプリの型に） | 527 | 0.2525 | 0/12 | 0/12 |
| **17g（+ 常体を外した）** | 527 | **0.2515** | 1/12 | 0/12 |

12件では 0/12 と 1/12 の差は誤差の範囲。17g の1件は「お前」で、口調の書き換えが
「君」に直している（安全網が効いている）。**17g を使う。** 常体のオウム返しは消えた。

`.litertlm` は `python/out/litertlm17g/model.litertlm`（1.90GB、WSL2 で約2分）。
実機で入れ替えるには、端末を繋いでから:

```
tool\dev_push_model.cmd out\litertlm17g\model.litertlm
tool\dev_bench.cmd
```

（`adb install -r` をすると端末側のモデル登録が消えるので、アプリを入れ直したら
「端末に置いたファイルから入れる」をもう一度押すこと。）

内容の傷はまだ残る。17g で見えた分: 「六桂の飛車」（事実にない駒を作る）、
大差で勝った場面で「参りました」（勝敗の取り違え）、悪手を「これも最善の手でございます」と
言い張る（-2461点の損を最善と呼ぶ）。**口調と形は片付いたが、意味はまだ甘い。**
これは数で効かせる話なので、2周目の126件へ。

2周目の書き込みシートは、実機で弱かった場面に寄せて 126件用意した
（move 41 / 煽り 19 / 褒め 18 / 読み聞かれ 10 / 悪手 16 / 詰めろ 5 / 終局 17）。
`--want move=100,...` で場面ごとの目標を指定できるようにした（`S` は1周目の記録として残す）。

## まだ確かめていないこと

- 内容の妥当性（「売上が見せてくれん」のような意味の崩れ）が、2周目の 126件でどこまで改善するか。
- それでも足りない場合、4bit 量子化を入れて 4B 級を学習するか、クラウドの GPU を借りるか。
- 1.90GB の `.litertlm` をどう配るか（nn.bin 64MB と同じ未決の問題）。
