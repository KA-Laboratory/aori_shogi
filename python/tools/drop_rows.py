"""all.jsonl から id を指定して行を落とす（機械的な除外のみ。文は書き換えない）。

  python tools/drop_rows.py move-composed-0011 move-composed-0013
"""
import json
import sys
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"
drop = set(sys.argv[1:])
rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
kept = [r for r in rows if r["id"] not in drop]
gone = {r["id"] for r in rows} & drop
path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in kept), encoding="utf-8")
print(f"{len(rows)} -> {len(kept)}  dropped={sorted(gone)}  missing={sorted(drop - gone)}")
