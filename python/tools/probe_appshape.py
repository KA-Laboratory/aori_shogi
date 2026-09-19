"""学習データの事実が、アプリが送る形と一致しているか場面ごとに数える。

アプリ側は game_controller.dart の _facts。ここの型はそれを写したもの。
一致しない行は、本番で来ない言い方を教えていることになる。
"""
import collections
import json
import re
import sys

W = "(優勢|互角|劣勢)"
SHAPES = {
    "move": rf"^\d+手目。形勢={W}（評価値[+-]\d+）。私の手 .+ (は最善。|は悪手で約\d+点損。)$",
    "praised": rf"^形勢={W}。相手に褒められた（[12]回目）。$",
    "praise_suspicious": r"^相手に\d+回続けて褒められた。$",
    "question_dodge": rf"^形勢={W}。相手に読みを聞かれた。教えない。$",
    "taunt_miss": r"^私の直前の手はほぼ最善。相手の煽りは外れ。$",
    "abuse": rf"^相手の発言は不適切。形勢={W}。$",
    "start": r"^対局開始。",
    "win": r"^相手が投了。",
    "lose": r"^私が投了した。",
}

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
tally = collections.Counter()
bad = collections.defaultdict(list)
for r in rows:
    pat = SHAPES.get(r["scene"])
    if not pat:
        continue
    if re.match(pat, r["facts"]):
        tally[r["scene"] + " 一致"] += 1
    else:
        tally[r["scene"] + " 不一致"] += 1
        bad[r["scene"]].append(f"{r['id']}  {r['facts']}")

out = [f"rows={len(rows)}", ""]
for k in sorted(tally):
    out.append(f"{tally[k]:4d}  {k}")
for scene, items in sorted(bad.items()):
    out += ["", f"[{scene} の不一致]"] + [f"  {i}" for i in items[:25]]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
