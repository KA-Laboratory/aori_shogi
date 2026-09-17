"""軍師の口調を揃える（assets/lines/gunshi_tone.json を Dart と共有）。

1. rewrite: よくある崩れ（です・ます、女性語、人称）を規則で置換する（決定的・無料）。
2. violations: 置換で直らなかった崩れを検出する → 生成側で作り直させる／テンプレートに切り替える。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

TONE_PATH = Path(__file__).resolve().parents[2] / "assets" / "lines" / "gunshi_tone.json"
_MARK = "⁣"  # 保護用の不可視区切り


class ToneProfile:
    def __init__(self, d: dict) -> None:
        self.summary: str = d["summary"]
        self.mood_notes: dict[str, str] = d.get("mood_notes", {})
        self.keep = sorted(d.get("keep_phrases", []), key=len, reverse=True)
        pairs = sorted(((a, b) for a, b in d["rewrites"]), key=lambda x: -len(x[0]))
        self._table = dict(pairs)
        self._rx = re.compile("|".join(re.escape(a) for a, _ in pairs))
        self.banned = [(re.compile(b["pattern"]), b["reason"]) for b in d["banned"]]
        self.mood_banned = {m: [(re.compile(b["pattern"]), b["reason"]) for b in lst]
                            for m, lst in d.get("mood_banned", {}).items()}
        # 気分によって許す崩れ（大混乱の乱暴な言葉は人間味として可）
        self.mood_allow: dict[str, set[str]] = {m: set(v) for m, v in d.get("mood_allow", {}).items()}

    @classmethod
    def load(cls, path: Path = TONE_PATH) -> "ToneProfile":
        return cls(json.loads(path.read_text(encoding="utf-8")))

    def _protect(self, s: str) -> tuple[str, list[str]]:
        saved: list[str] = []
        for k in self.keep:
            while k in s:
                saved.append(k)
                s = s.replace(k, f"{_MARK}{len(saved) - 1}{_MARK}", 1)
        return s, saved

    @staticmethod
    def _restore(s: str, saved: list[str]) -> str:
        return re.sub(f"{_MARK}(\\d+){_MARK}", lambda m: saved[int(m.group(1))], s)

    def rewrite(self, text: str) -> str:
        """長い語から1パスで置換（置換結果は再置換しない）。"""
        s, saved = self._protect(text)
        s = self._rx.sub(lambda m: self._table[m.group(0)], s)
        s = s.replace("だだ", "だ").replace("かかね", "かね")
        return self._restore(s, saved)

    def violations(self, text: str, mood: str | None = None) -> list[str]:
        s, _ = self._protect(text)
        rules = self.banned + (self.mood_banned.get(mood, []) if mood else [])
        allow = self.mood_allow.get(mood, set()) if mood else set()
        return [reason for rx, reason in rules if reason not in allow and rx.search(s)]

    def reminder(self, mood: str) -> str:
        note = self.mood_notes.get(mood, "")
        return f"[口調チェック（必ず守る）] {self.summary} 今の気分の口調: {note}"
