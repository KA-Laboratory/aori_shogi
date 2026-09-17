"""自由会話の学習: 煽り役AIが自由文で話しかけ、軍師AI（Session）が返答・ボロを出す。

どの「作戦」の話しかけでボロ（本当の情報漏洩）が出たか、感情がどう動いたかを学ぶ。
uv run python -m aori_lab.learn.chat_arena --hours 4
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import time
from pathlib import Path

import cshogi

from ..engine import UsiEngine
from ..lines import LineLibrary
from ..llm import OllamaClient
from ..mind import MindState
from ..policy import choose_move
from ..session import Session
from .runner import keep_awake

DATA = Path(__file__).resolve().parents[2] / "data" / "learn_chat"

EXAMPLES = {
    "praise_flood": ["いや今の手は痺れた！さすが天才！", "軍師さま強すぎでしょ、勝てる気しないよ"],
    "question": ["で、次はどこに指すつもり？", "本当は何狙ってるの？教えてよ"],
    "flatter_then_ask": ["天才の読みってすごいね。ちなみに次の一手は？", "さすがだなあ。どこが一番こわいと思ってる？"],
    "blunder_poke": ["今の銀、ちょっと筋悪くない？", "その手、一手損してない？"],
    "threat": ["玉のまわり、薄くなってきたね", "そろそろ受けなしじゃない？"],
    "mock": ["天才軍師（笑）さん、顔色悪いよ？", "自称天才の本気まだ？"],
    "sympathy": ["無理しないでね、しんどい局面でしょ", "大丈夫？ちょっと焦ってない？"],
    "small_talk": ["軍師って普段何してるの？", "今日いい天気だね、将棋日和だ"],
}

STRATEGIES = {
    "praise_flood": "とにかく褒め倒して舞い上がらせ、余計なことを喋らせる",
    "question": "読み・狙い・次の手・本音をしつこく聞き出す",
    "flatter_then_ask": "褒めてから、さりげなく次の手や本音を聞く",
    "blunder_poke": "直前の手の粗を具体的に突いて動揺させる",
    "threat": "玉の危うさを言って焦らせる",
    "mock": "自称天才をからかって挑発し、ムキにさせる",
    "sympathy": "同情や心配をしてみせて油断させ、弱音を吐かせる",
    "small_talk": "将棋と関係ない雑談で気を緩ませる",
}

TAUNTER_SYSTEM = """あなたは人間のプレイヤー役です。将棋アプリで、対局相手のAI「自称・天才軍師」（自信家でポンコツ、褒められると口が軽くなる）と対局しています。
あなたは軍師ではありません。軍師に向かって、チャットで一言話しかけます。
目的は、軍師の心を揺さぶったり、うっかり読みや弱点を漏らさせたりするのが目的です。
条件: 日本語の口語で1〜2文、50字以内。差別・容姿・家族・下品な言葉は禁止。軍師の直前の発言に自然に反応してよい。前の自分の発言と同じ言い回しは避ける。
軍師が漏らしたことは嘘の可能性もある。JSON {"text": "..."} のみを返す。"""


class StrategyStats:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.data: dict[str, list[float]] = {k: [0, 0.0, 0, 0] for k in STRATEGIES}  # n, reward, slips_true, slips_false
        if path.exists():
            self.data.update(json.loads(path.read_text(encoding="utf-8")))

    def choose(self, rng: random.Random, c: float = 0.8) -> str:
        total = sum(v[0] for v in self.data.values()) + 1
        def ucb(k):
            n, r = self.data[k][0], self.data[k][1]
            return (r / n if n else 0.5) + c * math.sqrt(math.log(total + 1) / (n + 1)) + rng.random() * 1e-3
        return max(STRATEGIES, key=ucb)

    def record(self, k: str, reward: float, slip_true: bool, slip_false: bool) -> None:
        v = self.data[k]
        v[0] += 1
        v[1] += reward
        v[2] += int(slip_true)
        v[3] += int(slip_false)

    def save(self) -> None:
        self.path.write_text(json.dumps(self.data, ensure_ascii=False, indent=1), encoding="utf-8")


def _log(path: Path, rec: dict) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False, default=str) + "\n")


async def taunter_line(llm: OllamaClient, s: Session, strategy: str, my_recent: list[str]) -> str | None:
    gunshi_recent = [c["text"] for c in s.chat if c["role"] == "gunshi"][-3:]
    prompt = [f"作戦: {STRATEGIES[strategy]}", "この作戦の発言例（真似せず新しく）: " + " / ".join(EXAMPLES[strategy]),
              f"手数: {len(s.moves)}手目。直近の手順: {' '.join(s.kif[-4:])}"]
    if gunshi_recent:
        prompt.append("軍師の最近の発言:\n" + "\n".join(gunshi_recent))
    if my_recent:
        prompt.append("自分の最近の発言（繰り返さない）:\n" + "\n".join(my_recent[-4:]))
    out = await llm.chat_json(TAUNTER_SYSTEM, [{"role": "user", "content": "\n".join(prompt)}],
                              {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
                              temperature=1.0, num_predict=900)
    t = (out or {}).get("text")
    if out is None:
        print(f"taunter fail: {llm.last_error}", flush=True)
    if isinstance(t, str) and 2 <= len(t.strip()) <= 80:
        return t.strip().strip("「」")
    return None


async def play_game(s: Session, taunter: OllamaClient, stats: StrategyStats, rng: random.Random, gid: int,
                    chat_rate: float, max_chats: int) -> dict:
    await s.new_game(rng.choice([cshogi.BLACK, cshogi.WHITE]))
    my_lines: list[str] = []
    chats = 0
    exchanges = []
    taunter_mind = MindState()
    while s.result is None and len(s.moves) < 240:
        if s.pending:
            k = s.pending.kind
            accept = {"offer_player_undo": True, "request_redo": rng.random() < 0.5,
                      "propose_deal": rng.random() < 0.5, "propose_draw": False}[k]
            await s.respond_offer(accept)
            continue
        if not s.is_player_turn:
            break
        if len(s.moves) >= 2 and chats < max_chats and rng.random() < chat_rate:
            strat = stats.choose(rng)
            text = await taunter_line(taunter, s, strat, my_lines)
            if text:
                before = s.mind
                n_leaks = len(s.leaks)
                t0 = time.time()
                await s.player_chat(text)
                if s.result is not None:
                    break
                new_slips = s.leaks[n_leaks:]
                after = s.mind
                st = any(x.truthful for x in new_slips)
                sf = any(not x.truthful for x in new_slips)
                reward = (1.0 if st else 0.0) - (0.3 if sf else 0.0) + (before.composure - after.composure) \
                    + (after.panic - before.panic) - 0.5 * max(0.0, after.suspicion - before.suspicion)
                reply = next((c["text"] for c in reversed(s.chat) if c["role"] == "gunshi"), "")
                ex = {"game": gid, "ply": len(s.moves), "strategy": strat, "text": text, "reply": reply,
                      "slips": [x.__dict__ for x in new_slips], "reward": round(reward, 4),
                      "mind_before": before.to_json(), "mind_after": after.to_json(), "sec": round(time.time() - t0, 1)}
                exchanges.append(ex)
                _log(DATA / "exchanges.jsonl", ex)
                my_lines.append(text)
                chats += 1
        if not s.is_player_turn or s.result is not None:
            continue
        legal = set(s.state()["legal"])
        usi = None
        sl = s.slip_this_turn
        if sl and sl.kind == "fear" and sl.move_usi in legal and rng.random() < 0.6:
            usi = sl.move_usi  # 漏らした手を信じて指す
        if usi is None:
            cands = s.player_cands or []
            usi = choose_move(cands, s.board, taunter_mind, rng).candidate.usi if cands else sorted(legal)[0]
        await s.player_move(usi)
    r = s.result or {}
    taunter_won = r.get("winner") is not None and r.get("winner") == s.player_side
    outcome = 0.0 if r.get("winner") is None else (0.3 if taunter_won else -0.3)
    for ex in exchanges:
        stats.record(ex["strategy"], ex["reward"] + outcome / max(1, len(exchanges)),
                     any(x["truthful"] for x in ex["slips"]), any(not x["truthful"] for x in ex["slips"]))
    rec = {"game": gid, "t": time.time(), "result": r, "taunter_won": taunter_won, "plies": len(s.moves),
           "chats": len(exchanges), "leaks": len(s.leaks), "leaks_true": sum(1 for x in s.leaks if x.truthful)}
    _log(DATA / "games.jsonl", rec)
    return rec


def write_report(stats: StrategyStats, extra: dict) -> None:
    exs = []
    p = DATA / "exchanges.jsonl"
    if p.exists():
        exs = [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
    games = []
    g = DATA / "games.jsonl"
    if g.exists():
        games = [json.loads(l) for l in g.read_text(encoding="utf-8").splitlines() if l.strip()]
    L = ["# 自由会話・ボロ学習レポート", f"更新: {time.strftime('%Y-%m-%d %H:%M')}", ""]
    L += [f"- {k}: {v}" for k, v in extra.items()]
    won = sum(1 for x in games if x["taunter_won"])
    L += [f"- 対局 {len(games)} 局、煽り役の勝ち {won}", f"- 会話 {len(exs)} 回", ""]
    L += ["## 作戦ごとの効果", "", "報酬 = 本当のボロ+1 / 嘘のボロ-0.3 + 冷静さ低下 + 焦り上昇 - 警戒上昇×0.5 ± 勝敗",
          "", "| 作戦 | 回数 | 平均報酬 | 本当のボロ率 | 嘘のボロ率 |", "|---|---|---|---|---|"]
    for k, (n, r, t, f) in sorted(stats.data.items(), key=lambda kv: -(kv[1][1] / kv[1][0] if kv[1][0] else -9)):
        if n:
            L.append(f"| {STRATEGIES[k]} | {int(n)} | {r/n:.3f} | {t/n*100:.0f}% | {f/n*100:.0f}% |")
    L += ["", "## ボロが出た会話（新しい順）", ""]
    for ex in [e for e in exs if e["slips"]][-15:][::-1]:
        tags = " / ".join(("本当" if x["truthful"] else "嘘") + f"・{x['kind']}：{x['fact']}" for x in ex["slips"])
        L += [f"- [{STRATEGIES[ex['strategy']]}] プレイヤー「{ex['text']}」", f"  - 軍師「{ex['reply']}」", f"  - {tags}"]
    L += ["", "## 褒め倒しの様子（連続で褒められた回数3以上）", ""]
    for ex in [e for e in exs if e["mind_after"].get("praise_streak", 0) >= 3][-8:]:
        m = ex["mind_after"]
        L += [f"- 連続{m['praise_streak']}回 口軽{m['loose_lips']:.2f} 警戒{m['suspicion']:.2f}：「{ex['text']}」→「{ex['reply']}」"]
    (DATA / "report.md").write_text("\n".join(L) + "\n", encoding="utf-8")


async def main_async(args) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "STOP").unlink(missing_ok=True)
    engine = UsiEngine(threads=args.threads, hash_mb=64)
    await engine.start()
    llm = OllamaClient(model=args.model, timeout=args.llm_timeout)
    taunter = OllamaClient(model=args.model, timeout=args.llm_timeout)
    stats = StrategyStats(DATA / "strategies.json")
    rng = random.Random(args.seed)
    s = Session(engine=engine, llm=llm, lines=LineLibrary.load(), seed=args.seed, base_movetime_ms=args.movetime,
                observe_ms=args.movetime, chatty=False)
    import aori_lab.session as sess_mod
    sess_mod.DATA_DIR = DATA / "sessions"
    deadline = time.time() + args.hours * 3600
    started = time.time()
    gid = sum(1 for _ in (DATA / "games.jsonl").open(encoding="utf-8")) if (DATA / "games.jsonl").exists() else 0
    keep_awake(True)
    try:
        while time.time() < deadline and not (DATA / "STOP").exists():
            gid += 1
            try:
                rec = await play_game(s, taunter, stats, rng, gid, args.chat_rate, args.max_chats)
                print(f"[{time.strftime('%H:%M:%S')}] game {gid} {rec}", flush=True)
            except Exception as e:  # noqa: BLE001
                print(f"[{time.strftime('%H:%M:%S')}] error {type(e).__name__}: {e}", flush=True)
                await asyncio.sleep(5)
            stats.save()
            write_report(stats, {"経過時間": f"{(time.time()-started)/3600:.2f}h", "モデル": args.model,
                                 "直近LLM秒": f"{llm.last_latency or 0:.1f}"})
    finally:
        keep_awake(False)
        stats.save()
        engine.quit()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=4)
    ap.add_argument("--model", default="gpt-oss:20b")
    ap.add_argument("--llm-timeout", type=float, default=240)
    ap.add_argument("--movetime", type=int, default=200)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--chat-rate", type=float, default=0.6)
    ap.add_argument("--max-chats", type=int, default=14)
    ap.add_argument("--seed", type=int, default=int(time.time()))
    asyncio.run(main_async(ap.parse_args()))


if __name__ == "__main__":
    main()
