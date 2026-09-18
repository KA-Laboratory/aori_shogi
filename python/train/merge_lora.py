"""LoRA をベースに焼き込んで safetensors で保存する。

  uv run python train/merge_lora.py --base Qwen/Qwen3-0.6B --adapter out/gunshi --out out/gunshi-merged

flutter_gemma も LiteRT-LM も「アダプタを実行時に差す」公開APIを持たないので、
マージした1つのモデルを配る（docs/dev/m3_llm_integration.md）。
このフォルダをそのまま litert-torch export_hf に渡せる。
"""
from __future__ import annotations

import argparse


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="Qwen/Qwen3-0.6B")
    ap.add_argument("--adapter", default="out/gunshi")
    ap.add_argument("--out", default="out/gunshi-merged")
    ap.add_argument("--shard", default="350MB", help="safetensors の分割サイズ")
    args = ap.parse_args()

    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    model = AutoModelForCausalLM.from_pretrained(args.base, dtype=torch.bfloat16, device_map="cpu")
    model = PeftModel.from_pretrained(model, args.adapter)
    model = model.merge_and_unload()
    # 1ファイル400MBの上限がある経路でも運べるように、分割して保存する
    model.save_pretrained(args.out, safe_serialization=True, max_shard_size=args.shard)
    AutoTokenizer.from_pretrained(args.adapter).save_pretrained(args.out)
    print(f"→ {args.out}。次は Linux で:")
    print(f"  litert-torch export_hf {args.out} out/litertlm -b -q dynamic_wi8_emb4_afp32 \\")
    print("      --externalize_embedder --cache_length 1024 --prefill_lengths 512 \\")
    print("      --experimental_lightweight_conversion True")


if __name__ == "__main__":
    main()
