"""棋力レベルどうしを戦わせて、レベルが本当に階段になっているかを測る。

uv run python tools/strength_ladder.py --games 12 --movetime 120
→ data/strength/ladder.json と ladder.md（勝率表・1手あたりの平均損失）
感情は固定（平静）にして、棋力レベルの差だけを見る。人間の相手は別途アプリで確かめる。
"""
from __future__ import annotations

import argparse
import asyncio
import itertools
import json
import random
import time
from pathlib import Path

import cshogi

from aori_lab.engine import UsiEngine
from aori_lab.mind import MindState
from aori_lab.policy import LEVELS, choose_move, movetime_for, multipv_for
from aori_lab.shogi_util import legal_moves_json

DATA = Path(__file__).resolve().parents[1] / "data" / "strength"
CALM = MindState()  # 感情なし（棋力だけを比べる）


async def play(engine: UsiEngine, black: str, white: str, movetime: int, rng: random.Random,
               max_plies: int = 260) -> dict:
    board = cshogi.Board()
    sfen, moves = board.sfen(), []
    losses = {black: [], white: []}
    winner, reason = None, "max_plies"
    while len(moves) < max_plies:
        if board.is_game_over():
            winner, reason = white if board.turn == cshogi.BLACK else black, "checkmate"
            break
        if board.is_draw(16) == cshogi.REPETITION_DRAW:
            reason = "repetition"
            break
        name = black if board.turn == cshogi.BLACK else white
        level = LEVELS[name]
        res = await engine.think(sfen, moves, movetime_for(CALM, movetime, level), multipv_for(CALM, level))
        legal = set(legal_moves_json(board))
        cands = [c for c in res.candidates if c.usi in legal]
        if not cands:
            winner, reason = (white if board.turn == cshogi.BLACK else black), "resign"
            break
        ch = choose_move(cands, board, CALM, rng, level=level)
        losses[name].append(ch.loss_cp)
        board.push_usi(ch.candidate.usi)
        moves.append(ch.candidate.usi)
    return {"black": black, "white": white, "winner": winner, "reason": reason, "plies": len(moves),
            "loss": {k: (sum(v) / len(v) if v else 0.0) for k, v in losses.items()}}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--games", type=int, default=12, help="1組あたりの対局数（先後を入れ替えて半分ずつ）")
    ap.add_argument("--movetime", type=int, default=120, help="1手の基準時間ms（レベルの倍率が掛かる）")
    ap.add_argument("--levels", default="beginner,easy,normal,strong,allOut")
    ap.add_argument("--threads", type=int, default=2)
    args = ap.parse_args()
    names = [n for n in args.levels.split(",") if n in LEVELS]
    engine = UsiEngine(threads=args.threads, hash_mb=64)
    await engine.start()
    rng = random.Random(0)
    DATA.mkdir(parents=True, exist_ok=True)
    games, t0 = [], time.time()
    try:
        for a, b in itertools.combinations(names, 2):
            for i in range(args.games):
                black, white = (a, b) if i % 2 == 0 else (b, a)
                g = await play(engine, black, white, args.movetime, rng)
                games.append(g)
                print(f"[{len(games)}] {black} 対 {white} → {g['winner'] or '引き分け'} "
                      f"({g['reason']}, {g['plies']}手, {time.time() - t0:.0f}s)", flush=True)
    finally:
        engine.quit()
    # 集計
    wins = {n: {m: [0, 0] for m in names} for n in names}  # [勝ち, 対局数]
    loss_sum = {n: [0.0, 0] for n in names}
    for g in games:
        a, b = g["black"], g["white"]
        for x, y in ((a, b), (b, a)):
            wins[x][y][1] += 1
            if g["winner"] == x:
                wins[x][y][0] += 1
        for n in (a, b):
            loss_sum[n][0] += g["loss"][n]
            loss_sum[n][1] += 1
    md = ["# 棋力レベルの階段（感情なし）", "",
          f"1手 {args.movetime}ms 基準 / 1組 {args.games}局 / 全{len(games)}局 / {(time.time() - t0) / 60:.0f}分", "",
          "## 勝率（行が勝った割合）", "", "| | " + " | ".join(names) + " |", "|---|" + "---|" * len(names)]
    for n in names:
        row = []
        for m in names:
            w, t = wins[n][m]
            row.append("-" if n == m or t == 0 else f"{w}/{t}")
        md.append(f"| {n}（{LEVELS[n].label}） | " + " | ".join(row) + " |")
    md += ["", "## 1手あたりの平均損失（cp、小さいほど強い）", ""]
    for n in names:
        s, c = loss_sum[n]
        md.append(f"- {n}（{LEVELS[n].label}）: {s / c:.0f}cp" if c else f"- {n}: 対局なし")
    md += ["", "引き分け・打ち切りは勝ちに数えていない。人間相手の手ごたえはアプリで確かめること。"]
    (DATA / "ladder.md").write_text("\n".join(md), encoding="utf-8")
    (DATA / "ladder.json").write_text(json.dumps({"args": vars(args), "games": games}, ensure_ascii=False),
                                      encoding="utf-8")
    print("\n".join(md[4:]))
    print("→ data/strength/ladder.md")


if __name__ == "__main__":
    asyncio.run(main())
