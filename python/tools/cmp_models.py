"""モデル比べ: finetune_gen を別々の出力先で回した結果を並べる。

uv run python tools/cmp_models.py cmp_gptoss cmp_qwen
不合格の理由・合格までの回数・1件あたりの秒数・平均文字数と、実物を10件ずつ出す。
"""
from __future__ import annotations

import collections
import json
import random
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"


def load(name: str) -> tuple[list[dict], collections.Counter]:
    d = DATA / name
    acc = [json.loads(l) for l in (d / "accepted.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()] \
        if (d / "accepted.jsonl").exists() else []
    rej = collections.Counter()
    if (d / "rejected.jsonl").exists():
        for l in (d / "rejected.jsonl").read_text(encoding="utf-8").splitlines():
            if l.strip():
                rej[json.loads(l)["reason"].split(":")[0]] += 1
    return acc, rej


def main() -> None:
    names = sys.argv[1:] or ["cmp_gptoss", "cmp_qwen"]
    rng = random.Random(0)
    for name in names:
        acc, rej = load(name)
        if not acc:
            print(f"== {name}: まだ結果なし")
            continue
        total = len(acc) + sum(rej.values())
        print(f"== {name}  合格 {len(acc)} / 生成 {total}（合格率 {len(acc) / total:.0%}）")
        print("   平均文字数", sum(len(r['line']) for r in acc) // len(acc))
        print("   不合格:", dict(rej.most_common()))
        for r in rng.sample(acc, min(8, len(acc))):
            print(f"   [{r['scene']}/{r['mood']}] {r['player'][:16]} → {r['line']}")
        print()


if __name__ == "__main__":
    main()
