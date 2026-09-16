"""テンプレートセリフ（Flutter 版と同じ assets/lines/gunshi_lines.json を共有）。"""
from __future__ import annotations

import json
import random
from pathlib import Path

LINES_PATH = Path(__file__).resolve().parents[2] / "assets" / "lines" / "gunshi_lines.json"


class LineLibrary:
    def __init__(self, table: dict[str, dict[str, list[str]]]) -> None:
        self.table = table

    @classmethod
    def load(cls, path: Path = LINES_PATH) -> "LineLibrary":
        return cls(json.loads(path.read_text(encoding="utf-8")))

    def lines_for(self, mood: str, trigger: str) -> list[str]:
        return self.table.get(mood, {}).get(trigger) or self.table.get("composed", {}).get(trigger) or []

    def pick(self, mood: str, trigger: str, rng: random.Random, **vars: str) -> str:
        lines = self.lines_for(mood, trigger)
        if not lines:
            return "……ふむ。"
        s = rng.choice(lines)
        for k, v in vars.items():
            s = s.replace("{" + k + "}", v)
        return s
