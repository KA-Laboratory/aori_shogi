"""学習データの場面×気分の本数を数える（どこを増やすか決めるため）。"""
import collections
import json
import sys

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
scene = collections.Counter(r["scene"] for r in rows)
mood = collections.Counter(r["mood"] for r in rows)
pair = collections.Counter((r["scene"], r["mood"]) for r in rows)
out = [f"rows={len(rows)}", "", "[場面]"]
out += [f"{v:4d}  {k}" for k, v in scene.most_common()]
out += ["", "[気分]"]
out += [f"{v:4d}  {k}" for k, v in mood.most_common()]
out += ["", "[場面×気分 が 3本以下]"]
out += [f"{v:4d}  {s}/{m}" for (s, m), v in sorted(pair.items()) if v <= 3]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
