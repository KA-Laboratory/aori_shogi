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

## 変換をどこで回すか

`litert-torch` は Linux のみ。選べる道は2つある。

- **(a) WSL2 を入れる**（`wsl --install` に管理者権限と再起動が要る。2026-09-19 時点で未導入）。
  学習も変換も1台で完結する。
- **(b) 学習とマージは Windows、変換だけ Linux に渡す。** 変換は上のとおり 2コア8GBで2分なので、
  重い作業ではない。マージ済みモデル（0.6B の bf16 で約1.2GB）を運ぶだけでよい。
  `merge_lora.py` は 350MB ずつに分けて保存するので、ファイル1つ400MBの上限がある経路でも運べる。

## まだ確かめていないこと

- 478件という小ささで口調が身につくか（足りなければ、同じ場面×気分の言い換えを増やす）。
- Gemma 3 1B の日本語で軍師の芸が成立するか。駄目なら E2B に上げる（2.4GB の配布が重い）。
- 変換にかかる時間とメモリ、量子化後の日本語の劣化。
