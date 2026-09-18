"""手直し用のひとまとめを作る: これまでの生成をぜんぶ集め、重複を消し、問題点を印にして並べる。

uv run python tools/build_edit_set.py
→ data/finetune_gen_edit/to_edit.jsonl（1行1件、scene→mood の順）と README.md
直したら: uv run python tools/check_edited.py data/finetune_gen_edit/to_edit.jsonl
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from aori_lab.learn.finetune_gen import (BAD_FACT, DEBRIS, MIN_LEN, MOOD_MARK, PERSONA_END, S, STIFF, MESS,
                                         Checker, squares)

DATA = Path(__file__).resolve().parents[1] / "data"
OUT = DATA / "finetune_gen_edit"
SOURCES = ["finetune_gen_v1", "finetune_gen_v2", "finetune_gen_v3", "finetune_gen_v4", "finetune_gen_v5",
           "cmp_gpt-oss_20b", "cmp_qwen3_8b"]
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]


def fix_facts(facts: str) -> str:
    """事実の数値だけ機械的に直す（将棋としてありえない小さな値を桁上げする）。"""
    def ev(m: re.Match) -> str:
        v = int(m.group(2))
        return f"{m.group(1)}{v * 100 if v else 50}{m.group(3)}"

    facts = re.sub(r"(評価値[±+-]?)([0-9]{1,2})([）)])", ev, facts)
    facts = re.sub(r"約([0-9]{1,2})点損", lambda m: f"約{max(60, int(m.group(1)) * 10)}点損", facts)
    return facts


def flags(r: dict, chk: Checker) -> list[str]:
    line, facts, player, mood = r["line"], r["facts"], r.get("player", ""), r["mood"]
    out = []
    if len(line) < MIN_LEN:
        out.append("短い")
    if len(line) > 90:
        out.append("90字超")
    if DEBRIS.search(line):
        out.append("JSONの破片")
    if STIFF.search(line):
        out.append("文語")
    if MESS.search(line):
        out.append("句読点の乱れ")
    if BAD_FACT.search(facts):
        out.append("事実の数値が不自然")
    if mood != "meltdown" and not PERSONA_END.search(line):
        out.append("語尾がキャラでない")
    mark = MOOD_MARK.get(mood)
    if mark and not mark.search(line):
        out.append("気分の印なし(任意)")
    v = chk.tone.violations(line, mood)
    if v:
        out.append("口調:" + ",".join(v))
    if squares(line) - squares(facts) - squares(player):
        out.append("事実にない指し手")
    if S[r["scene"]][3] == "空文字" and player:
        out.append("player不要")
    if S[r["scene"]][3] != "空文字" and not player:
        out.append("player欠落")
    return out


def main() -> None:
    chk = Checker()
    rows, seen = [], set()
    for src in SOURCES:
        p = DATA / src / "accepted.jsonl"
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            key = r["line"].strip()
            if key in seen:
                continue
            seen.add(key)
            r["source"] = src
            r["facts"] = fix_facts(r["facts"])
            rows.append(r)
    scenes = list(S)
    rows.sort(key=lambda r: (scenes.index(r["scene"]), MOODS.index(r["mood"]) if r["mood"] in MOODS else 9))
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "to_edit.jsonl").open("w", encoding="utf-8") as f:
        for i, r in enumerate(rows, 1):
            f.write(json.dumps({
                "id": f"{r['scene']}-{r['mood']}-{i:04d}",
                "scene": r["scene"], "mood": r["mood"],
                "facts": r["facts"], "player": r.get("player", ""), "line": r["line"],
                "flags": flags(r, chk), "keep": True, "source": r["source"], "model": r.get("model", ""),
            }, ensure_ascii=False) + "\n")
    bad = sum(1 for r in rows if flags(r, chk))
    target = {k: v[0] for k, v in S.items()}
    have: dict[str, int] = {}
    for r in rows:
        have[r["scene"]] = have.get(r["scene"], 0) + 1
    readme = [
        "# 手直し用データ", "",
        f"{len(rows)}件（重複を除いたもの）。うち{bad}件に指摘（flags）が付いています。", "",
        "## 直しかた", "",
        "- `to_edit.jsonl` を直接編集してください（1行1件のJSON）。",
        "- `line` を書き直す。`facts` の数値がおかしい行は `facts` も直してよい。",
        "- 要らない行は `\"keep\": false` にする（行を消しても構いません）。",
        "- `flags` は目安なので、消しても直さなくても構いません。", "",
        "## 指摘の意味", "",
        "- 短い: 18字未満。ひとことすぎて学習には弱い",
        "- 文語: 「である」「なり」「せよ」など。話し言葉に直す",
        "- 句読点の乱れ / JSONの破片: 生成の失敗",
        "- 事実の数値が不自然: 「約4点損」のような将棋としてありえない値（桁上げは機械的に直し済み。残っているものだけ手で）",
        "- 気分の印なし(任意): その気分らしい語（ふむ／はは／……／うわ など）が無いという目安。直さなくてよい",
        "- 語尾がキャラでない: 「〜だ」「〜かね」など軍師の語尾が無い",
        "- 気分が出ていない: 大混乱なのに落ち着いている、など",
        "- 口調: 女性語・です/ます・人称のぶれ", "",
        "## 場面ごとの件数（目標 / 今ある数）", "",
        "| scene | 目標 | 今 |", "|---|---|---|",
        *[f"| {k} | {target[k]} | {have.get(k, 0)} |" for k in S],
        "", "直し終わったら `uv run python tools/check_edited.py data/finetune_gen_edit/to_edit.jsonl` で確認できます。",
    ]
    (OUT / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")
    print(f"{len(rows)}件 → data/finetune_gen_edit/to_edit.jsonl（指摘つき {bad}件）")


if __name__ == "__main__":
    main()
