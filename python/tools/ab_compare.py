"""2つの条件のセリフを伏せて並べ、賢太郎さんがどちらが良いか選ぶための紙とその集計。

作る:  uv run python tools/ab_compare.py make data/eval/A.json data/eval/B.json
       → data/eval/ab_<時刻>.md（AとBを伏せて左右に出す）と ab_<時刻>.key.json
集計:  uv run python tools/ab_compare.py tally data/eval/ab_<時刻>.md
       → 各行の「左」「右」「同じ」を読み、どちらが勝ったかを出す（M3の受け入れ条件は過半数で勝つこと）
"""
from __future__ import annotations

import json
import random
import sys
import time
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "eval"


def make(a_path: str, b_path: str) -> None:
    a = json.loads(Path(a_path).read_text(encoding="utf-8"))
    b = json.loads(Path(b_path).read_text(encoding="utf-8"))
    rows_b = {(r["scene"], r["mood"], r["facts"]): r for r in b["rows"]}
    rng = random.Random(0)
    stamp = time.strftime("%Y%m%d_%H%M")
    key, out = [], ["# セリフの伏せ比べ", "",
                    f"条件1: {a['summary']['model']}（tone={a['summary']['tone_control']}）／"
                    f"条件2: {b['summary']['model']}（tone={b['summary']['tone_control']}）",
                    "", "各問の『判定』に 左 / 右 / 同じ のどれかを書いて保存してください。どちらがどの条件かは伏せてあります。", ""]
    n = 0
    for r in a["rows"]:
        m = rows_b.get((r["scene"], r["mood"], r["facts"]))
        if not m or r["line"] == m["line"]:
            continue
        n += 1
        left_is_a = rng.random() < 0.5
        left, right = (r, m) if left_is_a else (m, r)
        key.append({"no": n, "left": "A" if left_is_a else "B"})
        out += [f"## {n}. {r['scene']} / {r['mood']}", f"- 事実: {r['facts']}"]
        if r.get("player"):
            out.append(f"- 相手: {r['player']}")
        out += [f"- 左: {left['line']}", f"- 右: {right['line']}", "- 判定: ", ""]
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / f"ab_{stamp}.md").write_text("\n".join(out), encoding="utf-8")
    (DATA / f"ab_{stamp}.key.json").write_text(json.dumps(key, ensure_ascii=False), encoding="utf-8")
    print(f"{n}問 → data/eval/ab_{stamp}.md（答えは ab_{stamp}.key.json）")


def tally(md_path: str) -> None:
    p = Path(md_path)
    key_path = p.parent / f"{p.stem}.key.json"
    key = {k["no"]: k["left"] for k in json.loads(key_path.read_text(encoding="utf-8"))}
    no, score = 0, {"A": 0, "B": 0, "同じ": 0, "未回答": 0}
    for line in p.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            no = int(line[3:].split(".")[0])
        elif line.startswith("- 判定:"):
            v = line.split(":", 1)[1].strip()
            if v in ("左", "右"):
                left = key.get(no, "A")
                right = "B" if left == "A" else "A"
                score[left if v == "左" else right] += 1
            elif v in ("同じ", "同"):
                score["同じ"] += 1
            else:
                score["未回答"] += 1
    total = score["A"] + score["B"]
    print(score)
    if total:
        print(f"A {score['A']}勝 / B {score['B']}勝（引き分け {score['同じ']}、未回答 {score['未回答']}）"
              f" → {'A' if score['A'] > score['B'] else 'B' if score['B'] > score['A'] else '互角'}の勝ち")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "make":
        make(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "tally":
        tally(sys.argv[2])
    else:
        print(__doc__)
