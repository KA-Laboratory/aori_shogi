"""USI の info / bestmove 解析（Dart: usi_protocol.dart の移植）。"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Candidate:
    usi: str
    score_cp: int | None = None
    mate_in: int | None = None
    pv: tuple[str, ...] = ()

    @property
    def sort_score(self) -> int:
        return sort_score(self.score_cp, self.mate_in)


def sort_score(cp: int | None, mate: int | None) -> int:
    if mate is not None:
        return 100000 - mate if mate > 0 else -100000 - mate
    return cp or 0


@dataclass
class EngineInfo:
    depth: int | None = None
    score_cp: int | None = None
    mate_in: int | None = None
    multipv: int = 1
    nodes: int | None = None
    pv: list[str] = field(default_factory=list)
    bound: str | None = None

    @property
    def has_score(self) -> bool:
        return self.score_cp is not None or self.mate_in is not None


def parse_info(line: str) -> EngineInfo | None:
    t = line.split()
    if not t or t[0] != "info":
        return None
    info = EngineInfo()
    seen = False
    i = 1
    while i < len(t):
        tok = t[i]
        if tok == "depth" and i + 1 < len(t):
            info.depth = _int(t[i + 1]); i += 1
        elif tok == "nodes" and i + 1 < len(t):
            info.nodes = _int(t[i + 1]); i += 1
        elif tok == "multipv" and i + 1 < len(t):
            info.multipv = _int(t[i + 1]) or 1; i += 1
        elif tok == "score" and i + 2 < len(t):
            kind, raw = t[i + 1], t[i + 2]
            i += 2
            seen = True
            if kind == "cp":
                info.score_cp = _int(raw)
            elif kind == "mate":
                if raw in ("+", "-"):
                    info.mate_in = 1 if raw == "+" else -1
                else:
                    m = _int(raw)
                    if m == 0:
                        m = -1 if raw.startswith("-") else 1
                    info.mate_in = m
            if i + 1 < len(t) and t[i + 1] in ("lowerbound", "upperbound"):
                info.bound = t[i + 1]; i += 1
        elif tok == "pv":
            info.pv = t[i + 1 :]
            seen = True
            break
        elif tok == "string":
            return None
        i += 1
    return info if seen else None


def _int(s: str) -> int | None:
    try:
        return int(s)
    except ValueError:
        return None


class CandidateCollector:
    def __init__(self) -> None:
        self._latest: dict[int, EngineInfo] = {}
        self.depth: int | None = None

    def add(self, info: EngineInfo) -> None:
        if not info.pv or not info.has_score:
            return
        if info.bound is not None and info.multipv in self._latest:
            return
        self._latest[info.multipv] = info
        if info.depth is not None:
            self.depth = info.depth

    @property
    def candidates(self) -> list[Candidate]:
        return [
            Candidate(usi=i.pv[0], score_cp=i.score_cp, mate_in=i.mate_in, pv=tuple(i.pv))
            for _, i in sorted(self._latest.items())
        ]
