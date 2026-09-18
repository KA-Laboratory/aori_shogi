"""手直しした to_edit.jsonl を確認し、学習用に train/eval へ分ける。

uv run python tools/check_edited.py data/finetune_gen_edit/to_edit.jsonl
→ 残っている問題を一覧にし、問題なしの行を data/finetune_gen_edit/{train,eval}.jsonl に書き出す。
"""
from __future__ import annotations

import json
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.build_edit_set import flags  # noqa: E402
from aori_lab.learn.finetune_gen import Checker  # noqa: E402


def main() -> None:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "data/finetune_gen_edit/to_edit.jsonl")
    rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    kept = [r for r in rows if r.get("keep", True)]
    chk = Checker()
    bad = Counter()
    clean = []
    for r in kept:
        f = [x for x in flags(r, chk) if "(任意)" not in x]  # 任意の目安は除く
        if f:
            bad[f[0]] += 1
            print(f"[{r['id']}] {','.join(f)} | {r['line']}")
        else:
            clean.append(r)
    print(f"\n残した {len(kept)}件 / 全 {len(rows)}件、そのうち問題なし {len(clean)}件")
    if bad:
        print("残っている問題:", dict(bad.most_common()))
    rng = random.Random(0)
    by = defaultdict(list)
    for r in clean:
        by[r["scene"]].append(r)
    train, ev = [], []
    for rows_ in by.values():
        rows_ = rows_[:]
        rng.shuffle(rows_)
        k = round(len(rows_) * 0.1)
        ev += rows_[:k]
        train += rows_[k:]
    out = path.parent
    for name, rs in (("train.jsonl", train), ("eval.jsonl", ev)):
        (out / name).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rs), encoding="utf-8")
    print(f"→ {out}/train.jsonl {len(train)}件 / eval.jsonl {len(ev)}件")


if __name__ == "__main__":
    main()
