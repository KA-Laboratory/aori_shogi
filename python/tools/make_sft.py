"""学習データ（all.jsonl）を、追加学習（LoRA）に食わせる形にする。

uv run python tools/make_sft.py
→ data/finetune_gen_edit/sft_{train,eval}.jsonl

各行は {"messages": [{"role":"system",...},{"role":"user",...},{"role":"assistant",...}]}。
**アプリが実際に投げるプロンプトと同じ形**にしてある（lib/core/dialogue/speaker.dart の
LlmSpeaker.systemPrompt と buildUserPrompt の末尾）。ここがずれると、学習しても本番で効かない。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aori_lab.tone import ToneProfile  # noqa: E402

EDIT = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"
TONE = Path(__file__).resolve().parents[2] / "assets" / "lines" / "gunshi_tone.json"

# lib/core/dialogue/speaker.dart の LlmSpeaker.systemPrompt と同じ文面
SYSTEM = (
    "あなたは将棋アプリ「煽り将棋」の登場人物「自称・天才軍師」本人だ。"
    "自信満々だがどこか抜けている愛嬌のあるポンコツとして、プレイヤーと将棋を指している人として喋る。"
    "一人称は「私」、相手は「君」。セリフは日本語で1〜3文、90字以内。"
    "ト書き・括弧書き・絵文字・説明は書かない。将棋の内容は「事実」に書かれたことだけを根拠にし、"
    "事実にない指し手・駒・評価値を作らない。差別・容姿・人格攻撃・下品な言葉は書かない。"
    "セリフだけを返す。"
)


def user_prompt(row: dict, tone: ToneProfile) -> str:
    parts = [f"[事実] {row['facts']}"]
    player = (row.get("player") or "").strip()
    if player:
        parts.append(f"[相手の発言] {player}")
    # 口調の念押しは毎回いちばん最後（長い対話でペルソナが薄れるため）
    parts.append(tone.reminder(row["mood"]))
    return "\n\n".join(parts)


def main() -> None:
    tone = ToneProfile.load(TONE)
    for name in ("train", "eval"):
        src = EDIT / f"{name}.jsonl"
        rows = [json.loads(l) for l in src.read_text(encoding="utf-8").splitlines() if l.strip()]
        out = EDIT / f"sft_{name}.jsonl"
        with out.open("w", encoding="utf-8") as f:
            for r in rows:
                msg = {
                    "messages": [
                        {"role": "system", "content": SYSTEM},
                        {"role": "user", "content": user_prompt(r, tone)},
                        {"role": "assistant", "content": r["line"]},
                    ],
                    "scene": r["scene"],
                    "mood": r["mood"],
                }
                f.write(json.dumps(msg, ensure_ascii=False) + "\n")
        print(f"{len(rows)}件 → {out}")


if __name__ == "__main__":
    main()
