"""煽り役AI vs 軍師AI の自己対局。煽りの効果を報酬として記録する。"""
from __future__ import annotations

import json
import random
import time
from dataclasses import dataclass, field
from pathlib import Path

import cshogi

from ..engine import UsiEngine
from ..mind import MindState, TauntKind, apply_taunt, update_on_ai_turn, P as MP
from ..policy import choose_move, clamped, movetime_for, multipv_for
from ..shogi_util import legal_moves_json
from ..truth import TauntContext, judge_truth
from .pool import TauntEntry, TauntPool

TAUNTER_MIND = MindState()  # 煽り役は感情なし（初期値で固定）＝軍師と同じ棋力の基準線


def judged_effect(mind: MindState, entry: TauntEntry, truth: float, prev: TauntKind | None):
    j = entry.judgement
    assert j is not None
    kind = TauntKind(entry.kind)
    sting = j.sting_if_true if truth > 0 else j.sting_if_false
    out = apply_taunt(mind, kind, truth, prev, intensity=0.3 + 1.2 * sting / 10)
    after = out.after
    if truth <= 0 and kind != TauntKind.praise and j.sting_if_false >= 6:
        after = after.copy_with(composure=after.composure - 0.03 * (j.sting_if_false - 5))
    if j.backfire >= 6 and kind != TauntKind.praise:
        after = after.copy_with(composure=after.composure + 0.03 * (j.backfire - 5),
                                panic=after.panic - 0.02 * (j.backfire - 5))
    return after


def truth_bucket(t: float) -> str:
    return "hit" if t >= 1 else ("half" if t > 0 else "miss")


@dataclass
class ArenaConfig:
    movetime_ms: int = 120
    observe_ms: int = 120
    max_plies: int = 260
    control_every: int = 4  # N局に1局は煽りなし（対照）
    events_path: Path = Path("data/learn/events.jsonl")
    games_path: Path = Path("data/learn/games.jsonl")


@dataclass
class PendingTaunt:
    bucket: str
    entry_id: str | None
    imm: float
    kind: str
    truth: float
    delayed: float | None = None


@dataclass
class ArenaStats:
    games: int = 0
    started: float = field(default_factory=time.time)


class Arena:
    def __init__(self, engine: UsiEngine, pool: TauntPool, cfg: ArenaConfig, seed: int = 0) -> None:
        self.engine = engine
        self.pool = pool
        self.cfg = cfg
        self.rng = random.Random(seed)
        self.stats = ArenaStats()

    def _log(self, path: Path, rec: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    async def play_game(self) -> dict:
        cfg = self.cfg
        gid = self.stats.games + 1
        control = cfg.control_every > 0 and gid % cfg.control_every == 0
        gunshi = self.rng.choice([cshogi.BLACK, cshogi.WHITE])
        board = cshogi.Board()
        sfen = board.sfen()
        moves: list[str] = []
        mind = MindState()
        prev_kind: TauntKind | None = None
        pending: list[PendingTaunt] = []
        waiting_delay: PendingTaunt | None = None
        best_before: int | None = None
        player_cands = []
        ai_loss: int | None = None
        gunshi_losses: list[int] = []
        taunts = 0
        winner = None
        reason = "max_plies"

        while len(moves) < cfg.max_plies:
            if board.is_game_over():
                winner = 1 - board.turn
                reason = "checkmate"
                break
            d = board.is_draw(16)
            if d in (cshogi.REPETITION_DRAW,):
                reason = "repetition"
                break
            legal = set(legal_moves_json(board))
            if board.turn == gunshi:
                res = await self.engine.think(sfen, moves, movetime_for(mind, cfg.movetime_ms), multipv_for(mind))
                cands = [c for c in res.candidates if c.usi in legal]
                if not cands:
                    winner, reason = 1 - gunshi, "resign"
                    break
                mind = update_on_ai_turn(mind, cands[0].sort_score)
                ch = choose_move(cands, board, mind, self.rng)
                gunshi_losses.append(ch.loss_cp)
                if waiting_delay is not None:
                    waiting_delay.delayed = min(1.5, ch.loss_cp / 300)
                    waiting_delay = None
                best_before = clamped(cands[0])
                board.push_usi(ch.candidate.usi)
                moves.append(ch.candidate.usi)
                # 煽り役の番: 解析（候補手＝自分の指し手と図星判定を兼ねる）
                if board.is_game_over():
                    continue
                res2 = await self.engine.think(sfen, moves, cfg.observe_ms, 5)
                legal2 = set(legal_moves_json(board))
                player_cands = [c for c in res2.candidates if c.usi in legal2]
                if player_cands and best_before is not None:
                    ai_loss = max(0, best_before - (-clamped(player_cands[0])))
                    if ai_loss >= MP.cover_up_loss_cp:
                        mind = mind.copy_with(cover_up_turns=MP.cover_up_turns)
                continue

            # ---- 煽り役の手番
            if not player_cands:
                res2 = await self.engine.think(sfen, moves, cfg.observe_ms, 5)
                player_cands = [c for c in res2.candidates if c.usi in legal]
                if not player_cands:
                    winner, reason = gunshi, "resign"
                    break
            if not control:
                ctx = TauntContext(board, player_cands, ai_loss)
                truths = {k: judge_truth(k, ctx) for k in TauntKind}
                keys = ["none|-|" + mind.stance.value]
                for k in TauntKind:
                    if self.pool.usable(k.value):
                        keys.append(f"{k.value}|{truth_bucket(truths[k])}|{mind.stance.value}")
                key = self.pool.choose_bucket(keys, self.rng)
                kind_name = key.split("|")[0]
                before = mind
                entry = None
                if kind_name != "none":
                    kind = TauntKind(kind_name)
                    entry = self.pool.choose_entry(kind_name, self.rng)
                    if entry is not None:
                        mind = judged_effect(mind, entry, truths[kind], prev_kind)
                        prev_kind = kind
                        taunts += 1
                imm = (before.composure - mind.composure) + (mind.panic - before.panic)
                pt = PendingTaunt(bucket=key, entry_id=entry.id if entry else None, imm=imm, kind=kind_name,
                                  truth=truths[TauntKind(kind_name)] if kind_name != "none" else 0.0)
                pending.append(pt)
                waiting_delay = pt
                if entry is not None:
                    self._log(cfg.events_path, {"t": time.time(), "game": gid, "ply": len(moves), "entry": entry.id,
                                                "text": entry.text, "kind": kind_name, "truth": pt.truth,
                                                "stance": before.stance.value, "mood_before": before.mood.value,
                                                "mood_after": mind.mood.value, "d_comp": round(mind.composure - before.composure, 4),
                                                "d_panic": round(mind.panic - before.panic, 4)})
            ch = choose_move(player_cands, board, TAUNTER_MIND, self.rng)
            board.push_usi(ch.candidate.usi)
            moves.append(ch.candidate.usi)
            player_cands = []

        taunter_won = winner is not None and winner != gunshi
        outcome = 0.0 if winner is None else (0.3 if taunter_won else -0.3)
        for pt in pending:
            r = pt.imm + (pt.delayed or 0.0) + outcome
            self.pool.record_bucket(pt.bucket, r)
            if pt.entry_id and pt.entry_id in self.pool.entries:
                e = self.pool.entries[pt.entry_id]
                e.n += 1
                e.reward_sum += r
                e.comp_drop_sum += pt.imm
                e.induced_loss_sum += (pt.delayed or 0.0) * 300
                e.hits += 1 if pt.truth > 0 else 0
        self.stats.games += 1
        rec = {"t": time.time(), "game": gid, "control": control, "gunshi_side": gunshi, "winner": winner,
               "taunter_won": taunter_won, "reason": reason, "plies": len(moves), "taunts": taunts,
               "gunshi_avg_loss": sum(gunshi_losses) / len(gunshi_losses) if gunshi_losses else 0,
               "final_mind": mind.to_json()}
        self._log(cfg.games_path, rec)
        return rec
