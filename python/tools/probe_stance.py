"""事実の「形勢=」と「評価値」が食い違っている行を探す。

app 側（game_controller.dart の _facts）は評価値 >= +300 を優勢、<= -300 を劣勢、
その間を互角としている。学習データが違う呼び方をしていると、軍師が数字を
読めなくなる（実際 -1400 を「互角」と言う出力が出た）。
"""
import json
import re
import sys

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
bad = []
seen = 0
for r in rows:
    m = re.search(r"形勢=(\S+?)（評価値([+\-−]?\d+)）", r["facts"])
    if not m:
        continue
    seen += 1
    word, num = m.group(1), int(m.group(2).replace("−", "-").replace("+", ""))
    want = "優勢" if num >= 300 else "劣勢" if num <= -300 else "互角"
    if word != want:
        bad.append(f"{r['id']}  {word}（{num}） -> 本来 {want}\n      事実: {r['facts']}")
out = [f"「形勢=…（評価値…）」を持つ行: {seen}/{len(rows)}", f"食い違い: {len(bad)}", ""]
out += bad
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
