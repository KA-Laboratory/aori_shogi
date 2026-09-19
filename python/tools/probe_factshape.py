"""学習データの事実が、アプリが実際に送る形と合っているか調べる。

アプリ（game_controller.dart の _facts）が出す形は決まっている:
  形勢=優勢/互角/劣勢（評価値+N）
1周目のモデル生成由来の行には「形勢=持ち上がり」「形勢=微妙」「評価値±400」のような
アプリが絶対に出さない言い方が混ざっている。そういう行は、本番で来ない言葉を教え、
本番で来る言葉を教えないので、数の割に効かない。
"""
import collections
import json
import re
import sys

OK_STANCE = {"優勢", "互角", "劣勢"}
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
stance = collections.Counter()
weird_ev = []
for r in rows:
    for m in re.finditer(r"形勢=([^（(。]+)", r["facts"]):
        stance[m.group(1).strip()] += 1
    if re.search(r"評価値[±]", r["facts"]):
        weird_ev.append(r["id"])

out = [f"rows={len(rows)}", "", "[形勢= の言い方]"]
for k, v in stance.most_common():
    mark = "" if k in OK_STANCE else "   <- アプリは出さない"
    out.append(f"{v:4d}  {k}{mark}")
out += ["", f"[評価値± を含む行] {len(weird_ev)}"]
out += [f"  {i}" for i in weird_ev[:40]]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
