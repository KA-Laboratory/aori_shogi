import asyncio
import random

import cshogi

from aori_lab.learn.arena import Arena, ArenaConfig, judged_effect
from aori_lab.learn.forge import seed_pool
from aori_lab.learn.pool import Judgement, TauntEntry, TauntPool
from aori_lab.learn.report import export_candidates, write_report
from aori_lab.mind import MindState, TauntKind
from tests.test_session import FakeEngine


def judged_pool(tmp_path):
    pool = TauntPool(tmp_path / "pool.json")
    seed_pool(pool)
    for e in pool.entries.values():
        e.judgement = Judgement(sting_if_true=7, sting_if_false=2, backfire=1, kind=e.intended_kind,
                                hit_line="ぐぬぬ、今のは作戦だ！", miss_line="ははは、見当違いだな。")
    return pool


def test_judged_effect_scales_with_sting():
    m = MindState()
    strong = TauntEntry("強い", "blunderCall", "t", judgement=Judgement(sting_if_true=10, kind="blunderCall"))
    weak = TauntEntry("弱い", "blunderCall", "t", judgement=Judgement(sting_if_true=1, kind="blunderCall"))
    assert judged_effect(m, strong, 1.0, None).composure < judged_effect(m, weak, 1.0, None).composure
    rude = TauntEntry("失礼", "mock", "t", judgement=Judgement(sting_if_true=5, sting_if_false=5, backfire=10, kind="mock"))
    assert judged_effect(m, rude, 0.3, None).composure > judged_effect(m, TauntEntry("x", "mock", "t", judgement=Judgement(kind="mock", backfire=0)), 0.3, None).composure


def test_pool_roundtrip_and_ucb(tmp_path):
    pool = judged_pool(tmp_path)
    pool.save()
    again = TauntPool(tmp_path / "pool.json")
    assert len(again.entries) == len(pool.entries)
    assert not again.add(TauntEntry("いまの手、悪手でしょ！", "blunderCall", "g"))
    e = again.choose_entry("blunderCall", random.Random(0))
    assert e is not None and e.kind == "blunderCall"


def test_arena_game_and_report(tmp_path):
    pool = judged_pool(tmp_path)
    cfg = ArenaConfig(movetime_ms=1, observe_ms=1, max_plies=40, control_every=0,
                      events_path=tmp_path / "events.jsonl", games_path=tmp_path / "games.jsonl")
    arena = Arena(FakeEngine(), pool, cfg, seed=1)
    rec = asyncio.run(arena.play_game())
    assert rec["plies"] > 0
    assert sum(e.n for e in pool.entries.values()) == rec["taunts"]
    assert pool.bucket_stats
    write_report(pool, tmp_path, {"x": 1})
    ex = export_candidates(pool, tmp_path / "cand")
    assert ex["dataset"] == len(pool.entries)
    assert (tmp_path / "report.md").read_text(encoding="utf-8").startswith("# 煽り学習レポート")
