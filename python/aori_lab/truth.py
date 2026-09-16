"""図星判定（Dart: truth_judge.dart の移植）。"""
from __future__ import annotations

from dataclasses import dataclass, field

import cshogi

from .mind import MOCK_TRUTH, TauntKind
from .shogi_util import is_capture
from .usi import Candidate


@dataclass
class TauntContext:
    board: cshogi.Board  # プレイヤーが指す番の局面
    player_candidates: list[Candidate] = field(default_factory=list)
    last_ai_move_loss_cp: int | None = None


def judge_truth(kind: TauntKind, ctx: TauntContext) -> float:
    if kind == TauntKind.blunderCall:
        loss = ctx.last_ai_move_loss_cp
        if loss is None:
            return 0.0
        if loss >= 150:
            return 1.0
        if loss >= 50:
            return 0.5
        return 0.0
    best = ctx.player_candidates[0] if ctx.player_candidates else None
    if kind == TauntKind.hangingPiece:
        if best is None:
            return 0.0
        try:
            if not is_capture(ctx.board, best.usi):
                return 0.0
        except Exception:
            return 0.0
        return 1.0 if best.sort_score >= 150 else 0.5
    if kind == TauntKind.threat:
        if best is not None and best.mate_in is not None and best.mate_in > 0:
            return 1.0
        if best is not None and best.sort_score >= 1500:
            return 0.5
        return 0.0
    if kind == TauntKind.mock:
        return MOCK_TRUTH
    return 1.0
