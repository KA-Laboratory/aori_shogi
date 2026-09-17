"""candidates.jsonl の不合格のうち、崩れの修正（salvage）で合格するものを救って accepted.jsonl を作り直す。
uv run python tools/salvage_commentary.py
"""
import json

from aori_lab.learn.commentary import DATA, STYLE_QUOTES, salvage, validate

rows = [json.loads(l) for l in open(DATA / "candidates.jsonl", encoding="utf-8") if l.strip()]
acc, fixed = [], 0
for r in rows:
    if not r.get("ok") and "out" in r:
        o = salvage(r["out"])
        if not validate(o, r):
            r = {**r, "out": o, "ok": True, "errors": [], "salvaged": True}
            fixed += 1
    if r.get("ok"):
        acc.append(r)
with open(DATA / "accepted.jsonl", "w", encoding="utf-8") as f:
    for r in acc:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"candidates {len(rows)} accepted {len(acc)} (salvaged {fixed}) style_quotes {len(STYLE_QUOTES)}")
