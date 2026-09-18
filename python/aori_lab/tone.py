"""軍師の口調を揃える（assets/lines/gunshi_tone.json を Dart と共有）。

2026-09-18 から気分で口調が変わる:
- 平静・ドヤ顔・取り繕い → 慇懃な紳士口調（〜でございます／〜ですな）
- 動揺・大混乱 → 敬語が吹き飛んで素が出る（〜のだ／〜だぁ）

1. rewrite: よくある崩れ（女性語・人称）を規則で置換する。素が出る気分では敬語も常体に戻す。
2. violations: 直らなかった崩れと、気分に合っていない口調（丁寧さが足りない等）を検出する。
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
        self.plain_moods = set(d.get("plain_moods", []))

        def table(pairs):
            pairs = sorted(((a, b) for a, b in pairs), key=lambda x: -len(x[0]))
            return dict(pairs), re.compile("|".join(re.escape(a) for a, _ in pairs))

        self._table, self._rx = table(d["rewrites"])
        # 素が出る気分でだけ使う（です・ます → 常体）
        self._plain_table, self._plain_rx = table(d.get("rewrites_plain_moods", [])) \
            if d.get("rewrites_plain_moods") else ({}, None)
        self.banned = [(re.compile(b["pattern"]), b["reason"]) for b in d["banned"]]
        self.mood_banned = {m: [(re.compile(b["pattern"]), b["reason"]) for b in lst]
                            for m, lst in d.get("mood_banned", {}).items()}
        # 気分によって許す崩れ（大混乱の乱暴な言葉は人間味として可）
        self.mood_allow: dict[str, set[str]] = {m: set(v) for m, v in d.get("mood_allow", {}).items()}
        # 気分ごとに「入っていないといけない」印（丁寧さなど）
        self.mood_require = {m: [(re.compile(b["pattern"]), b["reason"]) for b in lst]
                             for m, lst in d.get("mood_require", {}).items()}

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

    def rewrite(self, text: str, mood: str | None = None) -> str:
        """長い語から1パスで置換（置換結果は再置換しない）。

        [mood] が素が出る気分（動揺・大混乱）のときは、です・ます も常体に戻す。
        """
        s, saved = self._protect(text)
        s = self._rx.sub(lambda m: self._table[m.group(0)], s)
        if self._plain_rx is not None and mood in self.plain_moods:
            s = self._plain_rx.sub(lambda m: self._plain_table[m.group(0)], s)
        s = s.replace("だだ", "だ").replace("かかね", "かね")
        return self._restore(s, saved)

    def violations(self, text: str, mood: str | None = None) -> list[str]:
        s, _ = self._protect(text)
        rules = self.banned + (self.mood_banned.get(mood, []) if mood else [])
        allow = self.mood_allow.get(mood, set()) if mood else set()
        out = [reason for rx, reason in rules if reason not in allow and rx.search(s)]
        # 「ございます」などは保護されて s から消えるので、元の文で見る
        for rx, reason in self.mood_require.get(mood or "", []):
            if not rx.search(text):
                out.append(reason)
        return out

    def reminder(self, mood: str) -> str:
        note = self.mood_notes.get(mood, "")
        return f"[口調チェック（必ず守る）] {self.summary} 今の気分の口調: {note}"
