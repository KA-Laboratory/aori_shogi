"""ボロ（口が滑る）: 軍師がうっかり読みや弱点を漏らす。本当のことも、嘘（ブラフ）もある。

コードが「漏らすか・何を・本当か嘘か」を決め、LLM は言い方だけを決める。
"""
from __future__ import annotations

import random
from dataclasses import dataclass

import cshogi

from .mind import MindState, Stance
from .shogi_util import kif_text
from .usi import Candidate

SLIP_KINDS = {
    "plan": "次に指すつもりの手を自慢げに漏らす",
    "fear": "相手に指されたら困る手を独り言で漏らす",
    "confess": "さっきの自分の手が失敗だったと本音を漏らす",
    "eval": "本当の形勢の見立てを漏らす",
}


@dataclass
class Slip:
    kind: str
    truthful: bool
    fact: str  # LLM に渡す「漏らす内容」（本人は隠しているつもり）
    move_usi: str | None = None  # plan: 軍師の手 / fear: 相手の手
    ply: int = 0


def slip_chance(m: MindState, question_bonus: float = 0.0) -> float:
    p = 0.02 + 0.55 * m.loose_lips + 0.15 * max(0.0, m.panic - 0.5) + 0.1 * max(0.0, m.hubris - 0.6) + question_bonus
    return max(0.0, min(0.8, p))


def truthful_chance(m: MindState) -> float:
    return max(0.15, min(0.9, 0.9 - 0.75 * m.suspicion))


def decide_slip(m: MindState, board: cshogi.Board, player_cands: list[Candidate], ai_loss: int | None,
                prev_usi: str | None, rng: random.Random, question_bonus: float = 0.0, ply: int = 0) -> Slip | None:
    """プレイヤーの手番の局面で呼ぶ。player_cands はプレイヤー視点の候補（pv 付き、最善が先頭）。"""
    if not player_cands or rng.random() >= slip_chance(m, question_bonus):
        return None
    truthful = rng.random() < truthful_chance(m)
    weights = {
        "plan": 1.0 + 2.0 * m.hubris,
        "fear": 0.5 + 2.5 * m.panic,
        "confess": (2.5 if (ai_loss or 0) >= 150 else 0.3) * (0.5 + m.panic),
        "eval": 0.6 + (1.0 if m.stance != Stance.even else 0.0),
    }
    kind = rng.choices(list(weights), weights=list(weights.values()))[0]
    best = player_cands[0]
    worst = player_cands[-1] if len(player_cands) > 1 else None

    if kind == "fear":
        c = best if truthful or worst is None else worst
        if not truthful and worst is None:
            truthful = True
        return Slip("fear", truthful, f"相手に{kif_text(board, c.usi, prev_usi)}と指されるのが実は一番こわい", c.usi, ply)

    if kind == "plan":
        src = best if truthful else (worst or best)
        if len(src.pv) < 2:
            return None
        b = board.copy()
        b.push_usi(src.pv[0])
        text = kif_text(b, src.pv[1], src.pv[0])
        if not truthful and src is best:
            truthful = True
        return Slip("plan", truthful, f"次は{text}で決めるつもりだ（相手の出方しだいだが）", src.pv[1], ply)

    if kind == "confess":
        loss = ai_loss or 0
        if truthful and loss >= 150:
            return Slip("confess", True, "さっきの自分の手は実は悪手だった", None, ply)
        if not truthful and loss < 50:
            return Slip("confess", False, "さっきの自分の手は実は悪手だった（本当はほぼ最善。油断を誘う嘘）", None, ply)
        kind = "eval"

    # eval
    real = m.stance
    if truthful:
        say = {Stance.dominant: "実はもう勝ちが見えている", Stance.even: "実はまだ互角で決め手がない", Stance.losing: "実はかなり苦しい"}[real]
    else:
        say = {Stance.dominant: "実はかなり苦しい", Stance.even: "実はもう勝ちが見えている", Stance.losing: "実はもう勝ちが見えている"}[real]
    return Slip("eval", truthful, say, None, ply)
