# 軍師の追加学習（LoRA）

道筋の全体は docs/dev/m3_lora_pipeline.md。ここは動かし方だけ。

## 1. データを作る

```
cd python
uv run python tools/make_sft.py
uv run python train/train_lora.py --dry_run    # 形の確認だけ
```

## 2. 学習に要るものを入れる（PC の GPU、Windows のままで可）

```
uv pip install "torch" --index-url https://download.pytorch.org/whl/cu124
uv pip install transformers peft trl datasets accelerate
```

4bit 量子化（bitsandbytes）は使わない。RTX 3070 Ti の 8GB なら 0.6B〜1B は bf16 + LoRA で収まる。

## 3. 学習

```
uv run python train/train_lora.py --base Qwen/Qwen3-0.6B --out out/gunshi-qwen3
```

- 既定は **Qwen3 0.6B**（Apache 2.0、HF の同意もトークンも要らない）。
- Gemma を使うなら `--base google/gemma-3-1b-it`。HF で利用規約に同意し、`huggingface-cli login` が要る。
- 478件と小さいので過学習しやすい。`eval_loss` が下げ止まったところを `load_best_model_at_end` が拾う。
- 学習するのは**軍師のセリフだけ**（`completion_only_loss=True`）。事実と相手の発言は入力として見せるだけ。

## 4. マージ

```
uv run python train/merge_lora.py --base Qwen/Qwen3-0.6B --adapter out/gunshi-qwen3 --out out/gunshi-merged
```

## 5. `.litertlm` に変換（**Linux が要る**）

```
uv tool install litert-torch-nightly
litert-torch export_hf out/gunshi-merged out/litertlm -b -q dynamic_wi8_emb4_afp32 \
    --externalize_embedder --cache_length 1024 --prefill_lengths 512 \
    --experimental_lightweight_conversion True
```

`--experimental_lightweight_conversion True` を付けないと、MLIR に落とす途中でメモリを使い切って落ちる。
付ければ 2コア8GB でも 2分程度で通る（素の Qwen3 0.6B で確認、出力 661MB）。

Windows には `litert-torch` が入らない。WSL2 を入れるか、変換だけ別の Linux に渡す
（マージ済みモデルは 350MB ずつに分けて保存されるので運びやすい）。
