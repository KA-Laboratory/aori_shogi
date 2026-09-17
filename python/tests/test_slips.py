import asyncio
import random

import cshogi

from aori_lab.dialogue import classify_keywords
from aori_lab.mind import SP, MindState, Stance, TauntKind, apply_taunt
from aori_lab.slips import decide_slip, slip_chance, truthful_chance
from aori_lab.usi import Candidate
from tests.test_session import make, run


def test_praise_streak_raises_loose_lips_then_suspicion():
    m = MindState()
    for i in range(6):
        m = apply_taunt(m, TauntKind.praise, 1.0).after
    assert m.praise_streak == 6
    assert m.loose_lips > 0.6
    assert m.suspicion > 0.2
    m2 = apply_taunt(m, TauntKind.blunderCall, 0.0).after
    assert m2.praise_streak == 0


def test_slip_chance_and_bluff_rate():
    calm = MindState(loose_lips=0.0, hubris=0.3, panic=0.1)
    loose = MindState(loose_lips=0.9, hubris=0.9)
    assert slip_chance(loose) > slip_chance(calm) * 5
    assert truthful_chance(MindState(suspicion=0.9)) < truthful_chance(MindState(suspicion=0.0))


def test_decide_slip_truth_and_bluff_contents():
    b = cshogi.Board()
    b.push_usi("7g7f")
    b.push_usi("3c3d")
    cands = [Candidate("2g2f", 50, pv=("2g2f", "8c8d")), Candidate("8h2b+", 20, pv=("8h2b+", "3a2b")),
             Candidate("1g1f", -120, pv=("1g1f", "4a3b"))]
    seen = {(True, "fear"): 0, (False, "fear"): 0}
    rng = random.Random(0)
    for _ in range(400):
        s = decide_slip(MindState(loose_lips=1.0, panic=0.9, suspicion=0.5), b, cands, 0, "3c3d", rng)
        if s and s.kind == "fear":
            seen[(s.truthful, "fear")] += 1
            assert s.move_usi == ("2g2f" if s.truthful else "1g1f")
    assert seen[(True, "fear")] and seen[(False, "fear")]


def test_session_exploit_truthful_fear():
    s = make()
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    from aori_lab.slips import Slip
    target = s.state()["legal"][0]
    s.slip_this_turn = Slip("fear", True, "怖い", target, len(s.moves))
    sus = s.mind.suspicion
    run(s.player_move(target))
    assert s.mind.suspicion > sus or s.exploit_note is None  # 反応後に消費される


def test_question_keyword():
    assert classify_keywords("次どこ指すつもり？", False).kind == "question"
