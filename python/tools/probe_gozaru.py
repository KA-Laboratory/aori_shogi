"""学習データの「ござ〜」の活用ぶりを数える（生成の「ございる」の出どころ調べ）。"""
import collections
import json
import re
import sys

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
c = collections.Counter()
for r in rows:
    c.update(re.findall(r"ござ[^\s。、！？]{0,3}", r["line"]))
out = [f"rows={len(rows)}"]
for k, v in c.most_common(20):
    out.append(f"{v:4d}  {k}")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
