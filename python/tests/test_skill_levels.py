"""棋力レベルが shared/skill_levels.json（Dart と共通）と一致していること。"""
import json
from pathlib import Path

from aori_lab.mind import MindState
from aori_lab.policy import LEVELS, PP, movetime_for, multipv_for, temperature_for

SHARED = Path(__file__).resolve().parents[2] / "shared" / "skill_levels.json"


def test_levels_match_shared_json():
    d = json.loads(SHARED.read_text(encoding="utf-8"))["levels"]
    assert set(d) == set(LEVELS)
    for name, want in d.items():
        got = LEVELS[name]
        assert (got.label, got.temp, got.multi_pv, got.movetime_scale) == (
            want["label"], float(want["temp"]), want["multi_pv"], float(want["movetime_scale"]))


def test_higher_level_is_stronger():
    calm = MindState()
    temps = [temperature_for(calm, LEVELS[n]) for n in ["beginner", "easy", "normal", "strong", "allOut"]]
    times = [movetime_for(calm, level=LEVELS[n]) for n in ["beginner", "easy", "normal", "strong", "allOut"]]
    assert temps == sorted(temps, reverse=True)
    assert times == sorted(times)


def test_emotion_adds_on_top():
    shaken = MindState(composure=0.2, panic=0.8)
    assert temperature_for(shaken, LEVELS["allOut"]) == 30.0 + PP.temp_composure * 0.8 + PP.temp_panic * 0.8
    assert multipv_for(shaken, LEVELS["normal"]) == LEVELS["normal"].multi_pv + PP.panic_multipv_bonus
