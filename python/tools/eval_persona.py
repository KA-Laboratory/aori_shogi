"""軍師キャラの評価: 評価用データ（eval.jsonl）で口調の崩れ・テンプレート落ち・速さを測る。

uv run python tools/eval_persona.py --model gpt-oss:20b            # 1条件を測る
uv run python tools/eval_persona.py --model qwen3:8b --no-tone     # 口調制御なしと比べる
出力: data/eval/<name>.json（1件ずつのセリフ入り）と標準出力のまとめ。
A/B の伏せ比べは tools/ab_compare.py。
M3 の受け入れ条件: 規則処理後の崩れ0%・テンプレート落ち≤5%・文句の重複なし。
"""
from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aori_lab.learn.finetune_gen import DATA as GEN_DATA  # noqa: E402
from aori_lab.learn.finetune_gen import squares, system_prompt  # noqa: E402
from aori_lab.lines import LineLibrary  # noqa: E402
from aori_lab.llm import OllamaClient  # noqa: E402
from aori_lab.tone import ToneProfile  # noqa: E402

DATA = Path(__file__).resolve().parents[1] / "data" / "eval"
SCHEMA = {"type": "object", "properties": {"line": {"type": "string"}}, "required": ["line"]}
# scene（学習データ）→ テンプレートの trigger（assets/lines/gunshi_lines.json）
TRIGGER = {"move": "move", "taunt_hit": "taunt_hit", "taunt_miss": "taunt_miss", "praised": "praised",
           "praise_suspicious": "praise_suspicious", "blunder_self": "blunder_self",
           "blunder_player": "blunder_player", "slip": "slip", "question_dodge": "question_dodge",
           "offer": "proposeDeal", "offer_reply": "offer_accepted", "smalltalk": "smalltalk",
           "ai_question": "question_dodge", "abuse": "abuse", "start": "start", "win": "win", "lose": "lose"}


def prompt(row: dict, tone: ToneProfile, lines: LineLibrary, tone_control: bool) -> str:
    ex = lines.lines_for(row["mood"], TRIGGER.get(row["scene"], "chat"))[:4]
    parts = [f"[事実] {row['facts']}"]
    if row.get("player"):
        parts.append(f"[相手の発言] {row['player']}")
    if ex:
        parts.append("[今の気分の口調の見本（そのまま使わず、今の状況に合わせて新しく言う）]\n" + "\n".join(ex))
    parts.append(f"[今言うこと] scene={row['scene']} / mood={row['mood']} の場面のセリフを1つ。事実にないことは言わない。")
    if tone_control:
        parts.append(tone.reminder(row["mood"]))
    parts.append('JSON {"line": "セリフ"} のみを返す。')
    return "\n\n".join(parts)


async def one(llm: OllamaClient, row: dict, tone: ToneProfile, lines: LineLibrary,
              tone_control: bool, retries: int) -> dict:
    sysmsg = system_prompt()
    user = prompt(row, tone, lines, tone_control)
    raw: list[str] = []
    t = time.monotonic()
    line = None
    for _ in range(1 + retries):
        out = await llm.chat_json(sysmsg, [{"role": "user", "content": user}], SCHEMA,
                                  temperature=0.8, num_predict=200)
        cand = (out or {}).get("line", "").strip()
        if not cand:
            continue
        raw.append(cand)
        fixed = tone.rewrite(cand) if tone_control else cand
        if not tone.violations(fixed, row["mood"]):
            line = fixed
            break
    sec = time.monotonic() - t
    bad_raw = bool(raw) and bool(tone.violations(raw[0], row["mood"]))
    fallback = line is None
    if fallback:  # テンプレートに落とす（遊べることを優先）
        line = lines.lines_for(row["mood"], TRIGGER.get(row["scene"], "chat"))[:1] or ["……ふむ。"]
        line = line[0]
    over = len(line) > 90
    unfounded = bool(squares(line) - squares(row["facts"]) - squares(row.get("player", "")))
    return {"id": row.get("id", ""), "scene": row["scene"], "mood": row["mood"], "facts": row["facts"],
            "player": row.get("player", ""), "reference": row.get("line", ""), "line": line,
            "raw": raw[:2], "sec": round(sec, 1), "bad_raw": bad_raw, "fallback": fallback,
            "over90": over, "unfounded": unfounded, "attempts": len(raw)}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="gpt-oss:20b")
    ap.add_argument("--input", default=str(GEN_DATA / "eval.jsonl"))
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--retries", type=int, default=2, help="崩れたら作り直す回数")
    ap.add_argument("--no-tone", action="store_true", help="口調制御（書き換え＋念押し）なしで測る")
    ap.add_argument("--name", default="")
    args = ap.parse_args()
    rows = [json.loads(l) for l in Path(args.input).read_text(encoding="utf-8").splitlines() if l.strip()][:args.limit]
    if not rows:
        print(f"入力がない: {args.input}")
        return
    DATA.mkdir(parents=True, exist_ok=True)
    tone, lines = ToneProfile.load(), LineLibrary.load()
    llm = OllamaClient(model=args.model, timeout=1800)
    if not await llm.available():
        print(f"モデルが見つからない: {args.model} ({llm.last_error})")
        return
    res = []
    for i, row in enumerate(rows, 1):
        r = await one(llm, row, tone, lines, not args.no_tone, args.retries)
        res.append(r)
        print(f"[{i}/{len(rows)}] {r['scene']}/{r['mood']} {r['sec']}s "
              f"{'落ち' if r['fallback'] else '可'} {r['line'][:40]}", flush=True)
    secs = sorted(r["sec"] for r in res)
    n = len(res)
    summary = {
        "model": args.model, "tone_control": not args.no_tone, "n": n,
        "崩れ_生成直後": sum(r["bad_raw"] for r in res) / n,
        "崩れ_処理後": sum(bool(tone.violations(r["line"], r["mood"])) and not r["fallback"] for r in res) / n,
        "テンプレート落ち": sum(r["fallback"] for r in res) / n,
        "90字超": sum(r["over90"] for r in res) / n,
        "事実にない指し手": sum(r["unfounded"] for r in res) / n,
        "同じ書き出し12字": n - len({r["line"][:12] for r in res}),
        "秒_中央値": statistics.median(secs), "秒_p95": secs[min(n - 1, int(n * 0.95))],
        "作り直し_平均": statistics.mean(r["attempts"] for r in res),
    }
    name = args.name or f"{args.model.replace(':', '_')}{'' if not args.no_tone else '_notone'}"
    (DATA / f"{name}.json").write_text(json.dumps({"summary": summary, "rows": res}, ensure_ascii=False, indent=1),
                                       encoding="utf-8")
    print("\n".join(f"{k}: {v:.2f}" if isinstance(v, float) else f"{k}: {v}" for k, v in summary.items()))
    print(f"→ data/eval/{name}.json")


if __name__ == "__main__":
    asyncio.run(main())
