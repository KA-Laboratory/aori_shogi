"""感情でエンジンの着手を変調する（Dart: move_policy.dart の移植）。"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass
from enum import Enum

import cshogi

from .mind import MindState
from .shogi_util import is_attacking_move
from .usi import Candidate


class PP:
    base_movetime_ms = 1500
    temp_base = 30.0
    temp_composure = 400.0
    temp_panic = 300.0
    hubris_threshold = 0.6
    hubris_attack_bonus_cp = 60
    blunder_panic_threshold = 0.7
    blunder_rate = 0.15
    blunder_min_loss_cp = 300
    blunder_max_loss_cp = 600
    mate_miss_panic = 0.9
    mate_miss_rate = 0.3
    normal_multipv = 5
    panic_multipv = 8
    score_clamp_cp = 5000


def movetime_for(s: MindState, base_ms: int = PP.base_movetime_ms) -> int:
    return round(base_ms * (0.4 + 0.6 * s.composure))


def multipv_for(s: MindState) -> int:
    return PP.panic_multipv if s.panic > PP.blunder_panic_threshold else PP.normal_multipv


def temperature_for(s: MindState) -> float:
    return PP.temp_base + PP.temp_composure * (1 - s.composure) + PP.temp_panic * s.panic


class Reason(str, Enum):
    best = "best"
    softmax = "softmax"
    hubrisAttack = "hubrisAttack"
    blunder = "blunder"
    mate = "mate"
    mateMissed = "mateMissed"


@dataclass(frozen=True)
class Choice:
    index: int
    candidate: Candidate
    loss_cp: int
    reason: Reason


def clamped(c: Candidate) -> int:
    return max(-PP.score_clamp_cp, min(PP.score_clamp_cp, c.sort_score))


def choose_move(
    candidates: list[Candidate],
    board: cshogi.Board,
    mind: MindState,
    rng: random.Random,
    modulate: bool = True,
) -> Choice:
    if not candidates:
        raise ValueError("no candidates")
    best = candidates[0]
    best_score = clamped(best)

    def pick(i: int, r: Reason) -> Choice:
        return Choice(i, candidates[i], max(0, best_score - clamped(candidates[i])), r)

    if not modulate or len(candidates) == 1:
        return pick(0, Reason.best)

    if best.mate_in is not None and best.mate_in > 0:
        miss = mind.panic > PP.mate_miss_panic and rng.random() < PP.mate_miss_rate
        if not miss:
            return pick(0, Reason.mate)
        others = [i for i in range(1, len(candidates)) if candidates[i].mate_in is None]
        if others:
            return pick(others[rng.randrange(len(others))], Reason.mateMissed)
        return pick(0, Reason.mate)

    if mind.panic > PP.blunder_panic_threshold and rng.random() < PP.blunder_rate * mind.panic:
        pool = [i for i in range(1, len(candidates))
                if PP.blunder_min_loss_cp <= best_score - clamped(candidates[i]) <= PP.blunder_max_loss_cp]
        if not pool:
            for i in range(len(candidates) - 1, 0, -1):
                if best_score - clamped(candidates[i]) >= PP.blunder_min_loss_cp:
                    pool.append(i)
                    break
        if pool:
            return pick(pool[rng.randrange(len(pool))], Reason.blunder)

    hubris_on = mind.hubris > PP.hubris_threshold
    t = temperature_for(mind)
    scores, bonus = [], []
    for c in candidates:
        s = float(clamped(c))
        b = False
        if hubris_on:
            try:
                if is_attacking_move(board, c.usi):
                    s += PP.hubris_attack_bonus_cp
                    b = True
            except Exception:
                pass
        scores.append(s)
        bonus.append(b)
    top = max(scores)
    weights = [math.exp(-(top - s) / t) for s in scores]
    r = rng.random() * sum(weights)
    chosen = len(weights) - 1
    for i, w in enumerate(weights):
        r -= w
        if r <= 0:
            chosen = i
            break
    reason = Reason.best if chosen == 0 else (Reason.hubrisAttack if bonus[chosen] else Reason.softmax)
    return pick(chosen, reason)
