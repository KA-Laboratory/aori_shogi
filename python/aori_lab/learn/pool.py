"""煽り文句プール（JSON 永続化）と、報酬統計・選択（UCB）。"""
from __future__ import annotations

import json
import math
import random
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path

from ..mind import TauntKind

KINDS = [k.value for k in TauntKind]


@dataclass
class Judgement:
    sting_if_true: int = 5
    sting_if_false: int = 2
    backfire: int = 2
    appropriate: bool = True
    kind: str = "mock"
    hit_line: str = ""
    miss_line: str = ""
    model: str = ""


@dataclass
class TauntEntry:
    text: str
    intended_kind: str
    source: str  # seed / generated
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:10])
    created: float = field(default_factory=time.time)
    style: str = ""
    judgement: Judgement | None = None
    n: int = 0
    reward_sum: float = 0.0
    comp_drop_sum: float = 0.0
    induced_loss_sum: float = 0.0
    hits: int = 0

    @property
    def kind(self) -> str:
        """効果計算に使う種類。生成時の意図を正とする（採点者の分類は分類器データ・一致率の確認用）。"""
        return self.intended_kind

    @property
    def judge_agrees(self) -> bool:
        return bool(self.judgement) and self.judgement.kind == self.intended_kind

    @property
    def usable(self) -> bool:
        return self.judgement is not None and self.judgement.appropriate and self.kind in KINDS

    @property
    def mean(self) -> float:
        return self.reward_sum / self.n if self.n else 0.0

    def prior(self) -> float:
        j = self.judgement
        if not j:
            return 0.0
        return (0.6 * j.sting_if_true + 0.4 * j.sting_if_false - 0.5 * j.backfire) / 10


class TauntPool:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.entries: dict[str, TauntEntry] = {}
        self.bucket_stats: dict[str, list[float]] = {}  # key -> [n, sum]
        if path.exists():
            self.load()

    # ---- 永続化
    def load(self) -> None:
        raw = json.loads(self.path.read_text(encoding="utf-8"))
        for e in raw.get("entries", []):
            j = e.pop("judgement", None)
            ent = TauntEntry(**e)
            ent.judgement = Judgement(**j) if j else None
            self.entries[ent.id] = ent
        self.bucket_stats = raw.get("bucket_stats", {})

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        data = {"saved": time.time(), "entries": [asdict(e) for e in self.entries.values()],
                "bucket_stats": self.bucket_stats}
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(self.path)

    # ---- 追加
    def has_text(self, text: str) -> bool:
        t = _norm(text)
        return any(_norm(e.text) == t for e in self.entries.values())

    def add(self, entry: TauntEntry) -> bool:
        if not entry.text or self.has_text(entry.text):
            return False
        self.entries[entry.id] = entry
        return True

    def unjudged(self) -> list[TauntEntry]:
        return [e for e in self.entries.values() if e.judgement is None]

    def usable(self, kind: str | None = None) -> list[TauntEntry]:
        return [e for e in self.entries.values() if e.usable and (kind is None or e.kind == kind)]

    # ---- 選択（UCB。事前値 = 採点）
    def choose_bucket(self, keys: list[str], rng: random.Random, c: float = 0.6) -> str:
        total = sum(self.bucket_stats.get(k, [0, 0])[0] for k in keys) + 1
        best, best_v = keys[0], -1e9
        for k in keys:
            n, s = self.bucket_stats.get(k, [0, 0.0])
            v = (s / n if n else 0.3) + c * math.sqrt(math.log(total + 1) / (n + 1)) + rng.random() * 1e-3
            if v > best_v:
                best, best_v = k, v
        return best

    def choose_entry(self, kind: str, rng: random.Random, c: float = 0.5) -> TauntEntry | None:
        cands = self.usable(kind)
        if not cands:
            return None
        total = sum(e.n for e in cands) + 1
        def score(e: TauntEntry) -> float:
            mean = (e.reward_sum + 2 * e.prior()) / (e.n + 2)
            return mean + c * math.sqrt(math.log(total + 1) / (e.n + 1)) + rng.random() * 1e-3
        return max(cands, key=score)

    def record_bucket(self, key: str, reward: float) -> None:
        st = self.bucket_stats.setdefault(key, [0, 0.0])
        st[0] += 1
        st[1] += reward


def _norm(s: str) -> str:
    return "".join(ch for ch in s if ch not in " 　、。！？!?「」…・ー〜~").lower()
