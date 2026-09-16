"""エンジン・LLM を差し替えて交渉の流れを検証する。"""
import asyncio
import random

import cshogi

from aori_lab.engine import SearchResult
from aori_lab.lines import LineLibrary
from aori_lab.mind import MindState, Stance
from aori_lab.session import Session
from aori_lab.usi import Candidate


class FakeEngine:
    """合法手を順に並べて評価値を付ける決定的なエンジン。"""

    def __init__(self, score=0):
        self.score = score

    async def think(self, sfen, moves, movetime, multipv):
        b = cshogi.Board(sfen)
        for m in moves:
            b.push_usi(m)
        legal = sorted(cshogi.move_to_usi(m) for m in b.legal_moves)
        cands = [Candidate(u, self.score - i * 40) for i, u in enumerate(legal[: max(1, multipv)])]
        return SearchResult(cands[0].usi, cands, 10)


def make(score=0):
    return Session(engine=FakeEngine(score), llm=None, lines=LineLibrary.load(), seed=1, base_movetime_ms=10, observe_ms=10)


def run(c):
    return asyncio.run(c)


def test_game_flow_and_player_undo_request():
    s = make()
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    assert len(s.moves) == 2 and s.is_player_turn
    # 慢心していなければ待ったは断るしかない
    assert not s._request_allowed("undo")
    s.mind = MindState(hubris=0.9, stance=Stance.dominant)
    assert s._request_allowed("undo")
    run(s._grant_request("undo"))
    assert s.moves == [] and s.is_player_turn


def test_request_redo_offer_accept():
    s = make()
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    from aori_lab.session import Offer
    s.pending = Offer("request_redo", len(s.moves), "置き直させて")
    before = list(s.moves)
    run(s.respond_offer(True))
    assert s.pending is None
    assert len(s.moves) == 2 and s.moves[0] == before[0]
    assert s.is_player_turn


def test_offer_ignored_by_moving():
    s = make()
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    from aori_lab.session import Offer
    s.pending = Offer("request_redo", len(s.moves), "置き直させて")
    legal = s.state()["legal"]
    assert legal == []  # 提案中は指せない（UI は受ける/断るを先に出す）
    s.pending = Offer("offer_player_undo", len(s.moves), "待ってやろうか")
    run(s.respond_offer(False))
    assert s.state()["legal"]


def test_chat_taunt_updates_mind_without_llm():
    s = make()
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    s.ai_loss = 300
    c0 = s.mind.composure
    run(s.player_chat("いまの手、悪手でしょ！"))
    assert s.mind.composure < c0
    assert s.chat[-1]["role"] == "gunshi"


def test_resign_request_when_losing():
    s = make(score=-3000)
    run(s.new_game(cshogi.WHITE))
    run(s.player_move("7g7f"))
    assert s._request_allowed("resign")
    run(s._grant_request("resign"))
    assert s.result["winner"] == cshogi.BLACK
