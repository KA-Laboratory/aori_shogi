"""軍師の口調を LoRA で覚えさせる（PC の GPU で回す）。

  uv run python train/train_lora.py --base Qwen/Qwen3-0.6B --out out/gunshi-qwen3

データは tools/make_sft.py が作る sft_{train,eval}.jsonl（アプリが実際に投げるプロンプトと同じ形）。
4bit 量子化は使わない（RTX 3070 Ti の 8GB なら 0.6B〜1B は bf16 + LoRA で収まるし、
Windows で bitsandbytes を入れる手間が要らない）。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"


def rows(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="Qwen/Qwen3-0.6B",
                    help="ベースモデル。Gemma は利用規約の同意と HF トークンが要る")
    ap.add_argument("--out", default="out/gunshi")
    ap.add_argument("--epochs", type=float, default=4.0)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--rank", type=int, default=16)
    ap.add_argument("--alpha", type=int, default=32)
    ap.add_argument("--batch", type=int, default=2)
    ap.add_argument("--accum", type=int, default=8)
    ap.add_argument("--max_len", type=int, default=768)
    ap.add_argument("--dry_run", action="store_true", help="データの確認だけして終わる")
    args = ap.parse_args()

    train = rows(DATA / "sft_train.jsonl")
    ev = rows(DATA / "sft_eval.jsonl")
    print(f"学習 {len(train)}件 / 評価 {len(ev)}件")
    print("--- 1件目 ---")
    for m in train[0]["messages"]:
        print(f"[{m['role']}] {m['content'][:120]}")
    if args.dry_run:
        return

    import torch
    from datasets import Dataset
    from peft import LoraConfig
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    tok = AutoTokenizer.from_pretrained(args.base)
    model = AutoModelForCausalLM.from_pretrained(
        args.base,
        dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
        device_map="cuda" if torch.cuda.is_available() else "cpu",
    )
    model.config.use_cache = False

    def strip(rs: list[dict]) -> Dataset:
        # scene / mood は検証用のメモなので学習には渡さない
        return Dataset.from_list([{"messages": r["messages"]} for r in rs])

    peft_config = LoraConfig(
        r=args.rank,
        lora_alpha=args.alpha,
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    )
    cfg = SFTConfig(
        output_dir=args.out,
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        per_device_train_batch_size=args.batch,
        gradient_accumulation_steps=args.accum,
        max_length=args.max_len,
        logging_steps=5,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=2,
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        warmup_steps=10,  # transformers 5.x に warmup_ratio は無い
        lr_scheduler_type="cosine",
        bf16=torch.cuda.is_bf16_supported(),
        gradient_checkpointing=True,
        report_to=[],
        # 学習するのは軍師のセリフだけ（事実と相手の発言は入力として見せるだけ）
        completion_only_loss=True,
    )
    trainer = SFTTrainer(
        model=model,
        args=cfg,
        train_dataset=strip(train),
        eval_dataset=strip(ev),
        processing_class=tok,
        peft_config=peft_config,
    )
    trainer.train()
    trainer.save_model(args.out)
    tok.save_pretrained(args.out)
    print(f"→ {args.out}（LoRA アダプタ）。次は train/merge_lora.py でベースに焼き込む")


if __name__ == "__main__":
    main()
