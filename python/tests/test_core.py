import json
import random
from pathlib import Path

import cshogi

from aori_lab.dialogue import classify_keywords, clean_speech
from aori_lab.mind import MindState, Mood, Stance, TauntKind, apply_taunt, update_on_ai_turn
from aori_lab.policy import Reason, choose_move, movetime_for, temperature_for
from aori_lab.shogi_util import board_json, is_capture, kif_text
from aori_lab.truth import TauntContext, judge_truth
from aori_lab.usi import Candidate, CandidateCollector, parse_info
from tools.gen_mind_vectors import OUT as VECTORS, st


def test_mood_table():
    assert MindState(cover_up_turns=1, panic=0.9).mood == Mood.coverUp
    assert MindState(panic=0.75).mood == Mood.meltdown
    assert MindState(stance=Stance.losing, composure=0.29, panic=0).mood == Mood.meltdown
    assert MindState(panic=0.45).mood == Mood.rattled
    assert MindState(stance=Stance.dominant, hubris=0.5).mood == Mood.smug
    assert MindState().mood == Mood.composed


def test_update_and_taunt_match_dart_examples():
    d = update_on_ai_turn(MindState(), 500)
    assert abs(d.hubris - 0.35) < 1e-9 and abs(d.composure - 0.83) < 1e-9
    hit = apply_taunt(MindState(), TauntKind.blunderCall, 1.0)
    assert abs(hit.after.composure - 0.55) < 1e-9 and abs(hit.after.panic - 0.30) < 1e-9


def test_shared_vectors_are_current():
    data = json.loads(Path(VECTORS).read_text(encoding="utf-8"))
    for c in data["cases"]:
        i = c["in"]
        s = MindState(i["composure"], i["hubris"], i["panic"], i["resistance"], Stance(i["stance"]), i["coverUpTurns"],
                      i["looseLips"], i["suspicion"], i["praiseStreak"])
        if c["op"] == "update":
            out = update_on_ai_turn(s, c["evalAi"], c["loss"])
        else:
            prev = TauntKind(c["prev"]) if c["prev"] else None
            out = apply_taunt(s, TauntKind(c["kind"]), c["truth"], prev, intensity=c["intensity"]).after
        assert st(out) == c["out"]
        assert movetime_for(s) == c["movetime"]


def test_usi_parse():
    i = parse_info("info depth 12 score cp -34 multipv 2 pv 7g7f 3c3d")
    assert i.depth == 12 and i.score_cp == -34 and i.multipv == 2 and i.pv == ["7g7f", "3c3d"]
    assert parse_info("info string hello") is None
    col = CandidateCollector()
    col.add(parse_info("info depth 1 score cp 50 multipv 1 pv 2g2f"))
    col.add(parse_info("info depth 2 score mate 3 multipv 1 pv 7g7f"))
    assert col.candidates[0].mate_in == 3


def test_policy():
    b = cshogi.Board()
    cands = [Candidate("2g2f", 50), Candidate("7g7f", 40), Candidate("5g5f", -100), Candidate("1g1f", -350), Candidate("9g9f", -500)]

    def avg(m):
        r = random.Random(7)
        return sum(choose_move(cands, b, m, r).loss_cp for _ in range(2000)) / 2000

    assert choose_move(cands, b, MindState(), random.Random(1), modulate=False).index == 0
    assert avg(MindState(composure=1, panic=0, hubris=0)) < avg(MindState()) < avg(MindState(composure=0.2, panic=0.8, hubris=0))
    mate = [Candidate("2g2f", mate_in=1), Candidate("7g7f", 3000)]
    assert choose_move(mate, b, MindState(composure=0, panic=0.85), random.Random(3)).reason == Reason.mate
    assert abs(temperature_for(MindState(composure=0.2, panic=0.8)) - 910) < 1e-9  # ふつう(350)＋感情


def test_truth_and_kif():
    b = cshogi.Board()
    for u in ["7g7f", "3c3d"]:
        b.push_usi(u)
    assert is_capture(b, "8h2b+")
    assert kif_text(b, "8h2b+") == "２二角成"
    ctx = TauntContext(b, [Candidate("8h2b+", 200)])
    assert judge_truth(TauntKind.hangingPiece, ctx) == 1.0
    assert judge_truth(TauntKind.blunderCall, TauntContext(b, [], 160)) == 1.0
    b.push_usi("8h2b+")
    assert kif_text(b, "3a2b", "8h2b+") == "同　銀"
    j = board_json(b)
    assert len(j["cells"]) == 81 and j["hands"][0] == [{"k": 5, "c": "角", "n": 1, "usi": "B"}]
    assert j["cells"][0]["sq"] == "9a" and j["cells"][0]["c"] == "香"


def test_keyword_classifier():
    assert classify_keywords("その角タダじゃん", False).kind == "hangingPiece"
    assert classify_keywords("待った！今のなし", False).request == "undo"
    assert classify_keywords("いいよ", True).request == "accept"
    assert classify_keywords("だめ", True).request == "decline"
    assert classify_keywords("ポンコツ軍師ｗ", False).kind == "mock"
    assert clean_speech("「ふふ（笑いながら）甘い」") == "ふふ甘い"
