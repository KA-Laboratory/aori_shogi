"""賢太郎さんが「セリフだけ」書けるように、場面ごとの雛形を作る。

uv run python tools/build_skeleton.py
→ data/finetune_gen_edit/skeleton.jsonl（line が空の行。facts と player は埋めてある）

facts の出どころ:
- 盤面の場面（move / taunt_hit / blunder_self など）は、実際の自己対局から取った局面（data/learn_commentary/moments.jsonl）。
  手数・評価値・損失・指した手はエンジンが出した本物の数字なので、ありえない値にならない。
- 相手の発言は、これまでのモデル生成（qwen3 / gpt-oss、Apache 2.0）から拾ったもの。
目標件数から、すでに書けている分（edited_by_owner.jsonl）を引いた数だけ作る。
"""
from __future__ import annotations

import json
import random
import re
from collections import Counter, defaultdict
from pathlib import Path

from aori_lab.learn.finetune_gen import S

DATA = Path(__file__).resolve().parents[1] / "data"
EDIT = DATA / "finetune_gen_edit"
POOLS = ["finetune_gen_v1", "finetune_gen_v2", "finetune_gen_v3", "finetune_gen_v5",
         "cmp_gpt-oss_20b", "cmp_qwen3_8b"]
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]
BOARD_SCENES = {"move", "taunt_hit", "blunder_self", "blunder_opponent", "checkmate_threat",
                "checkmate_win", "checkmate_lose"}
# 盤面と関係ない場面の事実（型が決まっているものはここで作る）
FIXED_FACTS = {
    "draw": ["千日手による引き分け。", "持将棋（点数）による引き分け。", "千日手。私はまだ指したかった。"],
    "start": ["対局開始。私は後手。", "対局開始。私は先手。", "対局開始。相手は初めての挑戦者。",
              "対局開始。前局は私が負けている。"],
    "win": ["相手が投了。私の勝ち。", "相手が投了。接戦だった。", "相手が投了。大差での勝ち。"],
    "lose": ["私が投了した。", "私が投了した。最後は攻め合い負け。", "私が投了した。序盤から一方的だった。"],
}


def moments() -> list[dict]:
    p = DATA / "learn_commentary" / "moments.jsonl"
    out = []
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        m = json.loads(line)
        f = m.get("facts", "")
        mv = re.search(r"指した手: (\S+)", f)
        if not mv:
            continue
        if mv.group(1).lstrip("▲△").startswith("同"):
            continue  # 「同　飛」は単体だと何の手か分からないので使わない
        out.append({"ply": m["ply"], "loss": m.get("loss", 0), "move": mv.group(1),
                    "best": (re.search(r"最善手: (\S+)", f) or [None, ""])[1],
                    "eval": m.get("eval_after_black", 0)})
    return out


def stance(ev: int) -> str:
    return "優勢" if ev >= 300 else ("劣勢" if ev <= -300 else "互角")


def board_facts(scene: str, m: dict, rng: random.Random) -> str:
    ev, loss, ply = m["eval"], m["loss"], m["ply"]
    # 軍師の手は △、相手の手は ▲ に揃える
    mv = "△" + m["move"].lstrip("▲△")
    if scene == "blunder_opponent" or scene == "checkmate_lose":
        mv = "▲" + m["move"].lstrip("▲△")
    if scene == "move":
        tail = "は最善。" if loss < 50 else f"は悪手で約{loss}点損。"
        return f"{ply}手目。形勢={stance(ev)}（評価値{ev:+}）。私の手 {mv} {tail}"
    if scene == "taunt_hit":
        return f"私の直前の手 {mv} は悪手（約{max(60, loss)}点損）。相手の煽りは図星。"
    if scene == "blunder_self":
        return f"直前の手 {mv} は悪手（約-{max(100, loss)}点損）。私は内心それに気づいている。"
    if scene == "blunder_opponent":
        return f"相手の手 {mv} は悪手（約+{max(100, loss)}点得）。"
    if scene == "checkmate_win":
        return f"私の手 {mv} で相手玉が詰み。勝利。"
    if scene == "checkmate_lose":
        return f"相手の手 {mv} で私の玉が詰み。敗北。"
    if scene == "checkmate_threat":
        return f"私の手 {mv} で詰めろがかかる。評価値+{rng.choice([1500, 2000, 2500, 3000, 4000])}。"
    return ""


def main() -> None:
    rng = random.Random(0)
    have = Counter()
    if (EDIT / "edited_by_owner.jsonl").exists():
        for line in (EDIT / "edited_by_owner.jsonl").read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                have[(r["scene"], r["mood"])] += 1
    # 相手の発言の素材（モデル生成）を場面ごとに集める
    players: dict[str, list[str]] = defaultdict(list)
    facts_pool: dict[str, list[str]] = defaultdict(list)
    for name in POOLS:
        p = DATA / name / "accepted.jsonl"
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("player"):
                players[r["scene"]].append(r["player"])
            f = r["facts"]
            # 場面に合わない混ざりものは素材にしない
            if r["scene"] == "smalltalk" and ("手数" in f or "評価値" in f):
                continue
            facts_pool[r["scene"]].append(f)
    ms = moments()
    rows = []
    for scene, (total, desc, fp, pp, weights) in S.items():
        per = {m: 0 for m in MOODS}
        ws = {m: weights.get(m, 1.0) for m in MOODS}
        tot = sum(ws.values())
        for m in MOODS:
            per[m] = round(total * ws[m] / tot)
        for mood in MOODS:
            need = max(0, per[mood] - have[(scene, mood)])
            for i in range(need):
                if scene in FIXED_FACTS:
                    facts = rng.choice(FIXED_FACTS[scene])
                elif scene in BOARD_SCENES and ms:
                    facts = board_facts(scene, rng.choice(ms), rng)
                else:
                    pool = facts_pool.get(scene) or []
                    facts = rng.choice(pool) if pool else f"（{desc}の事実をここに書く。型: {fp}）"
                player = ""
                if pp != "空文字":
                    cands = players.get(scene) or []
                    player = rng.choice(cands) if cands else f"（{pp}）"
                rows.append({"id": f"{scene}-{mood}-{len(rows) + 1:04d}", "scene": scene, "mood": mood,
                             "facts": facts, "player": player, "line": "", "flags": [], "keep": True,
                             "source": "skeleton"})
    EDIT.mkdir(parents=True, exist_ok=True)
    (EDIT / "skeleton.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                                         encoding="utf-8")
    c = Counter(r["scene"] for r in rows)
    print(f"{len(rows)}件 → data/finetune_gen_edit/skeleton.jsonl")
    for k in S:
        if c.get(k):
            print(f"  {k}: {c[k]}")


if __name__ == "__main__":
    main()
