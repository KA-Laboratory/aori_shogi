"""感情ロジックの共通テストベクタを生成する（Python 実装が正、Dart テストが同じ値を検証）。

uv run python tools/gen_mind_vectors.py  →  ../shared/mind_vectors.json
"""
import json
import random
from pathlib import Path

from aori_lab.mind import MindState, Stance, TauntKind, apply_taunt, update_on_ai_turn
from aori_lab.policy import movetime_for, multipv_for, temperature_for

OUT = Path(__file__).resolve().parents[2] / "shared" / "mind_vectors.json"


def st(d):
    return {"composure": round(d.composure, 10), "hubris": round(d.hubris, 10), "panic": round(d.panic, 10),
            "resistance": round(d.resistance, 10), "stance": d.stance.value, "coverUpTurns": d.cover_up_turns,
            "mood": d.mood.value, "looseLips": round(d.loose_lips, 10), "suspicion": round(d.suspicion, 10),
            "praiseStreak": d.praise_streak}


def main():
    rng = random.Random(20260916)
    cases = []
    for _ in range(200):
        s = MindState(composure=round(rng.random(), 2), hubris=round(rng.random(), 2), panic=round(rng.random(), 2),
                      resistance=round(rng.random() * 0.6, 2), stance=rng.choice(list(Stance)),
                      cover_up_turns=rng.choice([0, 0, 1, 2]), loose_lips=round(rng.random(), 2),
                      suspicion=round(rng.random() * 0.8, 2), praise_streak=rng.choice([0, 0, 1, 3, 4, 6]))
        op = rng.choice(["update", "taunt"])
        if op == "update":
            ev = rng.choice([-2000, -301, -300, -50, 0, 299, 300, 900])
            loss = rng.choice([None, 0, 199, 200, 500])
            out = update_on_ai_turn(s, ev, loss)
            cases.append({"op": op, "in": st(s), "evalAi": ev, "loss": loss, "out": st(out)})
        else:
            kind = rng.choice(list(TauntKind))
            truth = rng.choice([0.0, 0.3, 0.5, 1.0])
            prev = rng.choice([None, *list(TauntKind)])
            intensity = rng.choice([1.0, 1.0, 0.6, 1.2])
            out = apply_taunt(s, kind, truth, prev, intensity=intensity).after
            cases.append({"op": op, "in": st(s), "kind": kind.value, "truth": truth, "intensity": intensity,
                          "prev": prev.value if prev else None, "out": st(out)})
        cases[-1]["movetime"] = movetime_for(s)
        cases[-1]["multipv"] = multipv_for(s)
        cases[-1]["temperature"] = round(temperature_for(s), 10)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"version": 2, "cases": cases}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {len(cases)} cases -> {OUT}")


if __name__ == "__main__":
    main()
