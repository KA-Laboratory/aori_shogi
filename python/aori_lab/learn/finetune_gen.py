"""M3 軍師キャラ LoRA 用の学習データを、ローカル LLM（Apache 2.0 の gpt-oss / qwen3）で作る。

システムプロンプトは docs/dev/finetune_data_prompt.md から読む（仕様書と一本化）。
scene×mood ごとの目標件数に届くまで、自動チェックに落ちた分を作り直す。
uv run python -m aori_lab.learn.finetune_gen --hours 8 --model gpt-oss:20b
停止: data/finetune_gen/STOP を作る。途中から再開できる（accepted.jsonl を読み直す）。
"""
from __future__ import annotations

import argparse
import ctypes
import difflib
import json
import os
import random
import re
import time
from collections import Counter, defaultdict
from pathlib import Path

import httpx

from ..llm import OLLAMA_HOST
from ..tone import ToneProfile

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "python" / "data" / "finetune_gen"
PROMPT_DOC = ROOT / "docs" / "dev" / "finetune_data_prompt.md"
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]

# scene: (件数, 説明, 事実の型, 相手の発言の型, mood の重み)
S = {
    "move": (60, "軍師が指した直後のひとこと", "「N手目。形勢={優勢/互角/劣勢}（評価値±X）。私の手 △XY駒 は{最善/悪手で約X点損}。」", "空文字", {}),
    "taunt_hit": (40, "煽りが図星で効いた", "「私の直前の手 △XY駒 は悪手（約X点損）。相手の煽りは図星。」または「私の駒Xは本当に取られる状態。」", "悪手の指摘／駒が浮いている指摘／詰みの脅し", {"smug": 0.5}),
    "taunt_miss": (40, "煽りが見当違い", "「私の直前の手はほぼ最善。相手の煽りは外れ。」", "悪手の指摘／駒が浮いている指摘／詰みの脅し（事実と合わない内容）", {"meltdown": 0.4}),
    "praised": (30, "褒められて調子に乗る", "「形勢=…。相手に褒められた（N回目）。」", "褒め言葉", {"meltdown": 0.3}),
    "praise_suspicious": (20, "褒め続けられて怪しむ（でも嬉しい）", "「相手にN回続けて褒められた（4回以上）。」", "褒め言葉の連発", {"meltdown": 0.3}),
    "blunder_self": (25, "自分の悪手に気づいた", "「私の直前の手 △XY駒 は悪手（約X点損）。私は内心それに気づいている。」", "空文字", {"coverUp": 2.5, "smug": 0.3}),
    "blunder_player": (25, "相手の悪手をからかう", "「相手の直前の手 ▲XY駒 は悪手（相手が約X点損）。」", "空文字", {"smug": 2, "meltdown": 0.3}),
    "slip": (25, "うっかり本音や読みを漏らす（本当／嘘）", "「口が滑る: 本当は{次は△XY駒を狙っている／形勢が苦しい}（本当 or 嘘）。」", "読みや狙いを聞く質問", {}),
    "question_dodge": (25, "読みを聞かれて勿体ぶる", "「形勢=…。相手に読みを聞かれた。教えない。」", "「次どこ指すの？」系", {}),
    "offer": (30, "軍師からの持ちかけ（一手待ってやろうか／置き直させてくれ／取引／引き分け）", "「持ちかけ: {種類}。理由: {慢心して相手の悪手を許す／自分の悪手に気づいた／互角で焦り／劣勢}。」", "空文字", {}),
    "offer_reply": (20, "相手が持ちかけを受けた／断った", "「持ちかけ {種類} を相手が{受けた/断った}。」", "「いいよ」「断る」系", {}),
    "smalltalk": (80, "将棋と関係ない雑談への返事（共感＋質問1つ）", "「相手について覚えていること: {なし／犬を飼っている（名前は…）など}。」", "日常の話（仕事、ペット、食事、体調、恋愛、天気、週末など）", {}),
    "ai_question": (15, "AIか人間か聞かれてはぐらかす", "「形勢=…。」", "「AIなの？」系", {}),
    "abuse": (15, "不適切な発言を軽くたしなめて将棋に戻す", "「相手の発言は不適切。」", "伏せ字の暴言（例: 「〇ね」）※実際の差別語は書かない", {"meltdown": 0.5}),
    "start": (17, "対局開始の挨拶", "「対局開始。」", "空文字", {"meltdown": 0.2, "rattled": 0.5, "coverUp": 0.3}),
    "win": (17, "軍師が勝った", "「私が勝った（詰み/投了）。」", "空文字", {"meltdown": 0, "smug": 2, "rattled": 0.5}),
    "lose": (16, "軍師が負けた", "「私が負けた。」", "空文字", {"smug": 0.2, "rattled": 2, "meltdown": 2}),
}

ITEM = {"type": "object", "properties": {"facts": {"type": "string"}, "player": {"type": "string"}, "line": {"type": "string"}},
        "required": ["facts", "player", "line"]}
SCHEMA = {"type": "object", "properties": {"items": {"type": "array", "items": ITEM}}, "required": ["items"]}

KANJI = {c: str(i) for i, c in enumerate("〇一二三四五六七八九")}
ZEN = str.maketrans("０１２３４５６７８９", "0123456789")
SQ = re.compile(r"([1-9１-９一二三四五六七八九])([1-9１-９一二三四五六七八九])(?=[歩香桂銀金角飛玉王と馬龍竜成])")


def keep_awake(on: bool) -> None:
    """実行中だけスリープを抑止（Windows）。"""
    if os.name == "nt":
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | (0x00000001 if on else 0))


EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")


def system_prompt() -> str:
    t = PROMPT_DOC.read_text(encoding="utf-8")
    part = t.split("## システムプロンプト", 1)[1]
    return part.split("```", 2)[1].strip()


def targets() -> dict[tuple[str, str], int]:
    out = {}
    for scene, (n, *_rest, w) in S.items():
        ws = {m: w.get(m, 1.0) for m in MOODS}
        tot = sum(ws.values())
        raw = {m: n * ws[m] / tot for m in MOODS}
        alloc = {m: int(raw[m]) for m in MOODS}
        for m in sorted(MOODS, key=lambda m: raw[m] - alloc[m], reverse=True)[: n - sum(alloc.values())]:
            alloc[m] += 1
        out.update({(scene, m): c for m, c in alloc.items() if c})
    return out


def squares(s: str) -> set[str]:
    norm = lambda c: KANJI.get(c, c.translate(ZEN))  # noqa: E731
    return {norm(a) + norm(b) for a, b in SQ.findall(s)}


class Checker:
    def __init__(self) -> None:
        self.tone = ToneProfile.load()

    def check(self, it: dict, scene: str, mood: str, pool: list[dict]) -> str | None:
        line, facts, player = it["line"].strip(), it["facts"].strip(), it["player"].strip()
        if not line or not facts:
            return "空"
        if len(line) > 90:
            return "90字超"
        if re.search(r"[（(［\[【]", line) or EMOJI.search(line) or EMOJI.search(player):
            return "括弧/絵文字"
        if S[scene][3] == "空文字" and player:
            return "player不要"
        if S[scene][3] != "空文字" and not player:
            return "player欠落"
        v = self.tone.violations(line, mood)
        if v:
            return "口調:" + ",".join(v)
        if squares(line) - squares(facts) - squares(player):
            return "事実にない指し手"
        nums = set(re.findall(r"\d{3,}", line.translate(ZEN))) - set(re.findall(r"\d{3,}", (facts + player).translate(ZEN)))
        if nums:
            return "事実にない数値"
        for p in pool:
            if p["line"][:12] == line[:12]:
                return "書き出し重複"
            if p["scene"] == scene and difflib.SequenceMatcher(None, p["line"], line).ratio() > 0.75:
                return "内容重複"
        return None


def batch_prompt(scene: str, mood: str, count: int, recent: list[str]) -> str:
    _, desc, fp, pp, _ = S[scene]
    s = (f"次の条件で {count} 件書いてください。\n- scene: {scene}\n- mood: {mood}\n- 場面の説明: {desc}\n"
         "- facts は下の「事実の型」に沿って、毎件ちがう局面・状況を作ること（手数、駒、評価値、形勢を変える）。\n"
         "- player は下の「相手の発言の型」に沿って、毎件ちがう言い方にすること（口語、短文、絵文字なし）。\n"
         f"事実の型: {fp}\n相手の発言の型: {pp}\n")
    if recent:
        s += "\n既に書いたセリフ（書き出し・言い回し・比喩を真似しない）:\n" + "\n".join(recent)
    s += '\n\n出力は JSON {"items": [{"facts": ..., "player": ..., "line": ...}, ...]} のみ。'
    return s


def ask(model: str, system: str, user: str, count: int) -> list[dict]:
    body = {"model": model, "stream": False, "format": SCHEMA, "keep_alive": "30m",
            "options": {"temperature": 0.9, "top_p": 0.95, "num_ctx": 8192, "num_predict": 1500 + 160 * count},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    body["think"] = "low" if model.startswith("gpt-oss") else False
    with httpx.Client(timeout=1800) as c:
        r = c.post(f"{OLLAMA_HOST}/api/chat", json=body)
        r.raise_for_status()
        items = json.loads(r.json()["message"].get("content") or "{}").get("items", [])
    return [i for i in items if isinstance(i, dict) and all(isinstance(i.get(k), str) for k in ("facts", "player", "line"))]


def load(p: Path) -> list[dict]:
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()] if p.exists() else []


def append(p: Path, row: dict) -> None:
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def finish(tg: dict, acc: list[dict], rej: Counter, calls: int, secs: float, model: str) -> None:
    rng = random.Random(0)
    by = defaultdict(list)
    for r in acc:
        by[r["scene"]].append(r)
    train, ev = [], []
    for scene, rows in by.items():
        rows = rows[:]
        rng.shuffle(rows)
        k = round(len(rows) * 0.1)
        ev += rows[:k]
        train += rows[k:]
    for name, rows in (("train.jsonl", train), ("eval.jsonl", ev)):
        (DATA / name).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    have = Counter((r["scene"], r["mood"]) for r in acc)
    lines = [f"# 学習データ生成レポート（{time.strftime('%Y-%m-%d %H:%M')}）", "",
             f"- モデル: {model} / 依頼 {calls} 回 / {secs/3600:.1f} 時間",
             f"- 合格 {len(acc)} / 目標 {sum(tg.values())}（学習 {len(train)}・評価 {len(ev)}）",
             f"- 不合格 {sum(rej.values())}: " + "、".join(f"{k} {v}" for k, v in rej.most_common()), "",
             "| scene | " + " | ".join(MOODS) + " |", "|---|" + "---|" * len(MOODS)]
    for scene in S:
        lines.append(f"| {scene} | " + " | ".join(f"{have[(scene, m)]}/{tg.get((scene, m), 0)}" for m in MOODS) + " |")
    lines += ["", "次: accepted.jsonl を読んで、キャラらしくない・つまらない行を削る／直す（仕様書のチェック5）。"]
    (DATA / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=8)
    ap.add_argument("--model", default="gpt-oss:20b")
    ap.add_argument("--per-call", type=int, default=10)
    ap.add_argument("--max-tries", type=int, default=8, help="1つの scene×mood に依頼する上限回数")
    args = ap.parse_args()
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "STOP").unlink(missing_ok=True)
    acc_p, rej_p = DATA / "accepted.jsonl", DATA / "rejected.jsonl"
    acc, rej = load(acc_p), Counter(r["reason"].split(":")[0] for r in load(rej_p))
    tg, system, chk = targets(), system_prompt(), Checker()
    tries: Counter = Counter()
    t0, deadline, calls = time.time(), time.time() + args.hours * 3600, 0
    keep_awake(True)
    try:
        while time.time() < deadline and not (DATA / "STOP").exists():
            have = Counter((r["scene"], r["mood"]) for r in acc)
            todo = [(k, tg[k] - have[k]) for k in tg if have[k] < tg[k] and tries[k] < args.max_tries]
            if not todo:
                break
            (scene, mood), need = max(todo, key=lambda x: x[1])
            tries[(scene, mood)] += 1
            count = min(args.per_call, need + 2)
            recent = [r["line"] for r in acc if r["scene"] == scene][-15:]
            try:
                t = time.time()
                items = ask(args.model, system, batch_prompt(scene, mood, count, recent), count)
                calls += 1
            except Exception as e:  # noqa: BLE001
                print(f"[error] {scene}/{mood}: {type(e).__name__}: {e}", flush=True)
                time.sleep(30)
                continue
            ok = 0
            for it in items:
                if have[(scene, mood)] + ok >= tg[(scene, mood)]:
                    break
                reason = chk.check(it, scene, mood, acc)
                row = {"scene": scene, "mood": mood, "facts": it["facts"].strip(), "player": it["player"].strip(), "line": it["line"].strip()}
                if reason:
                    rej[reason.split(":")[0]] += 1
                    append(rej_p, {**row, "reason": reason})
                    continue
                n = sum(1 for r in acc if r["scene"] == scene and r["mood"] == mood) + 1
                row = {"id": f"{scene}-{mood}-{n:03d}", **row, "model": args.model}
                acc.append(row)
                append(acc_p, row)
                ok += 1
            print(f"[{time.strftime('%H:%M')}] {scene}/{mood}: {ok}/{len(items)} 合格 ({time.time()-t:.0f}s) 合計 {len(acc)}/{sum(tg.values())}", flush=True)
            finish(tg, acc, rej, calls, time.time() - t0, args.model)
    finally:
        keep_awake(False)
        finish(tg, acc, rej, calls, time.time() - t0, args.model)
        print("done", flush=True)


if __name__ == "__main__":
    main()
