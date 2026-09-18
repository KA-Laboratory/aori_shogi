"""手直し済みデータの残り課題と、場面ごとの不足数を出す。"""
from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.build_edit_set import flags  # noqa: E402
from aori_lab.learn.finetune_gen import S, Checker  # noqa: E402

path = Path(sys.argv[1] if len(sys.argv) > 1 else "data/finetune_gen_edit/edited_by_owner.jsonl")
rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
chk = Checker()
hard = [(r, [x for x in flags(r, chk) if x != "気分の印なし(任意)"]) for r in rows]
hard = [(r, f) for r, f in hard if f]
print(f"要確認 {len(hard)} / {len(rows)}")
for r, f in hard:
    print(f"- {r['id']} [{'/'.join(f)}]")
    print(f"    事実: {r['facts']}")
    print(f"    セリフ: {r['line']}")
have = collections.Counter(r["scene"] for r in rows)
print("\n場面ごと（今 / 目標）")
short = 0
for k, v in S.items():
    n = have.get(k, 0)
    short += max(0, v[0] - n)
    print(f"  {k}: {n} / {v[0]}")
print(f"\n合計 {len(rows)} 件、目標まであと {short} 件")
