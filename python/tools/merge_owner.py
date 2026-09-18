"""書けた分を all.jsonl に足す（id が同じなら差し替え）。

uv run python tools/merge_owner.py data/finetune_gen_edit/edited_by_owner_4.jsonl
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

EDIT = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"


def load(p: Path) -> list[dict]:
    if not p.exists():
        return []
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]


def main() -> None:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else EDIT / "edited_by_owner_4.jsonl")
    all_p = EDIT / "all.jsonl"
    rows = load(all_p)
    idx = {r["id"]: i for i, r in enumerate(rows)}
    add = rep = 0
    for r in load(src):
        if r["id"] in idx:
            rows[idx[r["id"]]] = r
            rep += 1
        else:
            rows.append(r)
            add += 1
    all_p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    print(f"差し替え {rep}件 / 追加 {add}件 → all.jsonl {len(rows)}件")


if __name__ == "__main__":
    main()
