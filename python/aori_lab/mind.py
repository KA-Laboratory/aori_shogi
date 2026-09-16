"""軍師の感情状態（Dart: lib/core/mind/mind_state.dart と taunts.dart の移植）。

数値は Dart 版と同一に保つこと。shared/mind_vectors.json で両者を検証する。
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from enum import Enum


class Stance(str, Enum):
    dominant = "dominant"
    even = "even"
    losing = "losing"

    @property
    def label(self) -> str:
        return {"dominant": "優勢", "even": "互角", "losing": "劣勢"}[self.value]

    @staticmethod
    def from_eval(eval_ai: int) -> "Stance":
        if eval_ai >= P.stance_threshold:
            return Stance.dominant
        if eval_ai <= -P.stance_threshold:
            return Stance.losing
        return Stance.even


class Mood(str, Enum):
    composed = "composed"
    smug = "smug"
    rattled = "rattled"
    meltdown = "meltdown"
    coverUp = "coverUp"

    @property
    def label(self) -> str:
        return {"composed": "平静", "smug": "ドヤ顔", "rattled": "動揺", "meltdown": "大混乱", "coverUp": "取り繕い"}[
            self.value
        ]


class P:
    """MindParams（Dart と共通）。"""

    stance_threshold = 300
    initial_composure = 0.8
    initial_hubris = 0.3
    initial_panic = 0.1
    recovery_per_move = 0.03
    hubris_gain_dominant = 0.05
    panic_gain_losing = 0.06
    resistance_same_kind = 0.15
    resistance_other_kind = -0.05
    cover_up_loss_cp = 200
    cover_up_turns = 2


def _clip(v: float) -> float:
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


@dataclass(frozen=True)
class MindState:
    composure: float = P.initial_composure
    hubris: float = P.initial_hubris
    panic: float = P.initial_panic
    resistance: float = 0.0
    stance: Stance = Stance.even
    cover_up_turns: int = 0

    def copy_with(self, **kw) -> "MindState":
        for k in ("composure", "hubris", "panic", "resistance"):
            if k in kw:
                kw[k] = _clip(kw[k])
        return replace(self, **kw)

    @property
    def mood(self) -> Mood:
        return mood_for(self)

    def to_json(self) -> dict:
        d = asdict(self)
        d["stance"] = self.stance.value
        d["mood"] = self.mood.value
        return d


def mood_for(s: MindState) -> Mood:
    if s.cover_up_turns > 0:
        return Mood.coverUp
    if s.panic >= 0.75 or (s.stance == Stance.losing and s.composure < 0.3):
        return Mood.meltdown
    if s.panic >= 0.45 or s.composure < 0.45:
        return Mood.rattled
    if s.stance == Stance.dominant and s.hubris >= 0.5:
        return Mood.smug
    return Mood.composed


def update_on_ai_turn(s: MindState, eval_ai: int, last_ai_move_loss_cp: int | None = None) -> MindState:
    stance = Stance.from_eval(eval_ai)
    c = s.composure + P.recovery_per_move
    p = s.panic - P.recovery_per_move
    h = s.hubris
    if stance == Stance.dominant:
        h += P.hubris_gain_dominant
    if stance == Stance.losing:
        p += P.panic_gain_losing
    if stance != Stance.dominant:
        h -= P.recovery_per_move
    cover = s.cover_up_turns - 1 if s.cover_up_turns > 0 else 0
    if last_ai_move_loss_cp is not None and last_ai_move_loss_cp >= P.cover_up_loss_cp:
        cover = P.cover_up_turns
    return s.copy_with(composure=c, hubris=h, panic=p, stance=stance, cover_up_turns=cover)


class TauntKind(str, Enum):
    blunderCall = "blunderCall"
    hangingPiece = "hangingPiece"
    threat = "threat"
    mock = "mock"
    praise = "praise"


@dataclass(frozen=True)
class TauntEffect:
    composure: float = 0.0
    hubris: float = 0.0
    panic: float = 0.0


TAUNT_HIT: dict[TauntKind, TauntEffect] = {
    TauntKind.blunderCall: TauntEffect(composure=-0.25, panic=0.20),
    TauntKind.hangingPiece: TauntEffect(composure=-0.20, panic=0.15),
    TauntKind.threat: TauntEffect(composure=-0.10, panic=0.30),
    TauntKind.mock: TauntEffect(composure=-0.15, panic=0.05),
    TauntKind.praise: TauntEffect(composure=0.10, hubris=0.10),
}
TAUNT_MISS = TauntEffect(composure=0.05, hubris=0.05)
MOCK_TRUTH = 0.3
MOCK_BACKFIRE_HUBRIS = 0.6


@dataclass(frozen=True)
class TauntOutcome:
    before: MindState
    after: MindState
    truth: float
    kind: TauntKind

    @property
    def hit(self) -> bool:
        return self.truth > 0 and self.kind != TauntKind.praise

    @property
    def composure_delta(self) -> float:
        return self.after.composure - self.before.composure

    @property
    def panic_delta(self) -> float:
        return self.after.panic - self.before.panic


def apply_taunt(
    s: MindState,
    kind: TauntKind,
    truth: float,
    previous_kind: TauntKind | None = None,
    intensity: float = 1.0,
) -> TauntOutcome:
    """煽りを感情に反映する。[intensity] は自由文の強さ（定型スタンプは 1.0、Dart 版と一致）。"""
    rf = (1 - s.resistance) * intensity
    if kind == TauntKind.praise:
        e = TAUNT_HIT[kind]
        nxt = s.copy_with(composure=s.composure + e.composure * rf, hubris=s.hubris + e.hubris * rf)
    elif kind == TauntKind.mock and s.hubris > MOCK_BACKFIRE_HUBRIS:
        nxt = s.copy_with(composure=s.composure + TAUNT_MISS.composure)
    elif truth <= 0:
        nxt = s.copy_with(composure=s.composure + TAUNT_MISS.composure, hubris=s.hubris + TAUNT_MISS.hubris)
    else:
        e = TAUNT_HIT[kind]
        k = truth * rf
        nxt = s.copy_with(
            composure=s.composure + e.composure * k,
            hubris=s.hubris + e.hubris * k,
            panic=s.panic + e.panic * k,
        )
    dr = P.resistance_same_kind if previous_kind == kind else P.resistance_other_kind
    nxt = nxt.copy_with(resistance=nxt.resistance + dr)
    return TauntOutcome(before=s, after=nxt, truth=truth, kind=kind)
