"""直したい行を、事実・相手・セリフ・出どころつきで UTF-8 に書き出す。

  python tools/dump_rows.py <out.txt> [--odd] [--pm]
    --odd  アプリが出さない形勢の言い方を含む行
    --pm   「評価値±」を含む行
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"
OK = {"優勢", "互角", "劣勢"}

rows = [json.loads(l) for l in PATH.read_text(encoding="utf-8").splitlines() if l.strip()]
want_odd, want_pm = "--odd" in sys.argv, "--pm" in sys.argv
out = []
for r in rows:
    m = re.search(r"形勢=([^（(。]+)", r["facts"])
    odd = bool(m) and m.group(1).strip() not in OK
    pm = "評価値±" in r["facts"]
    if (want_odd and odd) or (want_pm and pm):
        out.append(
            f"--- {r['id']}  [{r['scene']}/{r['mood']}]  src={r.get('source', '?')}\n"
            f"事実: {r['facts']}\n"
            f"相手: {r.get('player', '')}\n"
            f"セリフ: {r['line']}"
        )
Path(sys.argv[1]).write_text(f"{len(out)}件\n\n" + "\n\n".join(out) + "\n", encoding="utf-8")
print(f"{len(out)}件")
