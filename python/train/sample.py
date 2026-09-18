"""学習したモデルに、評価用のお題を投げて実際のセリフを見る。

  uv run python train/sample.py --model out/gunshi-merged --n 12
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aori_lab.tone import ToneProfile  # noqa: E402

EDIT = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"
TONE = Path(__file__).resolve().parents[2] / "assets" / "lines" / "gunshi_tone.json"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="out/gunshi-merged")
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tone = ToneProfile.load(TONE)
    rows = [json.loads(l) for l in (EDIT / "sft_eval.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    random.Random(args.seed).shuffle(rows)
    rows = rows[: args.n]

    tok = AutoTokenizer.from_pretrained(args.model)
    model = AutoModelForCausalLM.from_pretrained(args.model, dtype=torch.bfloat16, device_map="cuda")
    model.eval()

    bad = 0
    for r in rows:
        msgs = r["messages"][:2]
        prompt = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True, enable_thinking=False)
        ids = tok(prompt, return_tensors="pt").to(model.device)
        t0 = time.time()
        with torch.no_grad():
            out = model.generate(**ids, max_new_tokens=80, do_sample=True, temperature=0.9, top_k=40,
                                 pad_token_id=tok.eos_token_id)
        text = tok.decode(out[0][ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()
        fixed = tone.rewrite(text, r["mood"])
        v = tone.violations(fixed, r["mood"])
        if v:
            bad += 1
        print(f"[{r['scene']}/{r['mood']}] {time.time() - t0:.1f}s")
        print(f"  事実: {msgs[1]['content'].splitlines()[0][:70]}")
        print(f"  出力: {text}")
        if fixed != text:
            print(f"  整形: {fixed}")
        if v:
            print(f"  崩れ: {v}")
        print(f"  手本: {r['messages'][2]['content']}")
    print(f"\n崩れ {bad}/{len(rows)}")


if __name__ == "__main__":
    main()
