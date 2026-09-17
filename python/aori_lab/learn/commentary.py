"""解説文・煽り文の自前生成（ライセンスの心配がない学習/セリフ素材を作る）。

1. やねうら王の自己対局（ときどき次善手を選んで悪手を混ぜる）
2. 節目の局面（悪手・詰み筋・大駒の取り合い）で、評価値・最善手・読み筋を「事実」として抜き出す
3. LLM（既定 gpt-oss:20b）に事実だけを渡し、解説文・プレイヤーの煽り・軍師の反応を書かせる
4. コードで検証（事実にない指し手を書いていないか、長さ、種類）→ 候補ファイルへ（アプリには未反映。レビュー後に採用）

uv run python -m aori_lab.learn.commentary --hours 3
停止: data/learn_commentary/STOP を作る
"""
from __future__ import annotations

import argparse
import asyncio
import json
import random
import re
import time
from pathlib import Path

import cshogi

from ..engine import UsiEngine
from ..llm import OllamaClient
from ..shogi_util import PIECE_KANJI, SIDE_LABEL, captured_name, kif_text
from ..usi import Candidate
from .runner import keep_awake

DATA = Path(__file__).resolve().parents[2] / "data" / "learn_commentary"
KINDS = ["blunderCall", "hangingPiece", "threat", "mock", "praise"]
MOODS = ["smug", "composed", "rattled", "panic"]
MOVE_RE = re.compile(r"(?:同\s*|[１-９1-9][一二三四五六七八九])(?:成香|成桂|成銀|歩|香|桂|銀|金|角|飛|玉|王|と|馬|龍|竜)(?:成|不成|打)?")
SCHEMA = {
    "type": "object",
    "properties": {
        "commentary": {"type": "string"},
        "taunts": {"type": "array", "items": {"type": "object", "properties": {
            "kind": {"type": "string", "enum": KINDS}, "text": {"type": "string"}}, "required": ["kind", "text"]}},
        "gunshi": {"type": "object", "properties": {
            "mood": {"type": "string", "enum": MOODS}, "text": {"type": "string"}}, "required": ["mood", "text"]},
    },
    "required": ["commentary", "taunts", "gunshi"],
}
SYSTEM = """あなたは将棋の解説者兼、対局アプリ「煽り将棋」の台本作家です。
与えられた【事実】だけを根拠に書きます。事実にない指し手・駒・評価を作ってはいけません。
- commentary: 観戦者向けの解説。60〜100字。指し手は事実に書かれた表記（例: ７六歩、同　角成）だけを使う。
- taunts: プレイヤーが相手（自称天才軍師のAI）に言う煽りを3つ。各10〜35字、口語。kind は
  blunderCall=悪手の指摘 / hangingPiece=駒が浮いている・タダ / threat=詰み・寄せの脅し / mock=からかい / praise=褒め殺し。
  局面に合う kind を選ぶ（悪手の直後なら blunderCall、詰み筋なら threat など）。3つのうち最低2つは事実に即した指摘にする。
- gunshi: 煽られた軍師（尊大だが抜けているポンコツ）の一言。10〜40字。mood は形勢に合わせる（有利=smug、互角=composed、不利=rattled、大差や詰み=panic）。
【事実】の「指した手で取った相手の駒」は、指した側が得た駒（失った駒ではない）。形勢の数値は先手から見た値で、プラスは先手有利。
JSON だけを出力。"""
FEWSHOT_FACTS = "手番: ▲先手 42手目\n指した側から見た形勢: 互角 → 不利\n形勢(先手から): +120 → -380（悪手、損失500）\n指した手: ▲４五桂\n最善手: ▲６六角 / 読み筋: ６六角 同　歩 ５五銀\n指した手で取った相手の駒: なし\n局面: 中盤"
FEWSHOT_OUT = {
    "commentary": "▲４五桂は勢いのある跳ねですが、ここは▲６六角で中央を支えるのが本筋でした。桂が取られる筋が残り、形勢は一気に後手に傾きました。",
    "taunts": [{"kind": "blunderCall", "text": "今の４五桂、完全に勇み足でしょ"},
               {"kind": "hangingPiece", "text": "その桂馬、帰り道ないけど大丈夫？"},
               {"kind": "mock", "text": "天才軍師さん、顔が引きつってるよ"}],
    "gunshi": {"mood": "rattled", "text": "け、桂馬は囮だ！計算通りなのだ…たぶん"},
}


def clamp_score(c: Candidate) -> int:
    if c.mate_in is not None:
        return 3000 if c.mate_in > 0 else -3000
    return max(-3000, min(3000, c.score_cp or 0))


def phase(ply: int) -> str:
    return "序盤" if ply < 30 else ("中盤" if ply < 80 else "終盤")


class CommentaryForge:
    def __init__(self, args) -> None:
        self.args = args
        self.rng = random.Random(args.seed)
        self.engine = UsiEngine(threads=args.threads)
        self.llm = OllamaClient(model=args.model, timeout=args.llm_timeout)
        self.started = time.monotonic()
        DATA.mkdir(parents=True, exist_ok=True)
        self.stats = {"games": 0, "moments": 0, "generated": 0, "valid": 0, "llm_fail": 0}

    def done(self) -> bool:
        return (DATA / "STOP").exists() or time.monotonic() - self.started > self.args.hours * 3600 or (
            self.args.max_moments and self.stats["generated"] >= self.args.max_moments)

    def log(self, msg: str) -> None:
        line = f"{time.strftime('%H:%M:%S')} {msg}"
        print(line, flush=True)
        with open(DATA / "forge.log", "a", encoding="utf-8") as f:
            f.write(line + "\n")

    # ---- 1. 自己対局と節目の抽出
    async def play_and_extract(self, gid: int) -> list[dict]:
        board = cshogi.Board()
        moves: list[str] = []
        prev_eval: int | None = None  # 手番側から
        prev_cands: list[Candidate] = []
        moments: list[dict] = []
        noise = self.rng.choice([0.05, 0.15, 0.3])
        while not board.is_game_over() and len(moves) < 220:
            res = await self.engine.think(board.sfen(), [], self.args.movetime, multipv=4)
            cands = sorted(res.candidates, key=lambda c: -c.sort_score) or [Candidate(res.bestmove)]
            eval_stm = clamp_score(cands[0])
            if moves and prev_eval is not None:
                loss = prev_eval - (-eval_stm)  # 直前に指した側の損失
                last = moves[-1]
                mover = 1 - board.turn
                was_best = bool(prev_cands) and prev_cands[0].usi == last
                decided = abs(prev_eval) >= 1500
                interesting = (loss >= 150 and not was_best and not decided) or bool(cands[0].mate_in)
                if interesting and len([m for m in moments if m["ply"] > len(moves) - 6]) == 0:
                    moments.append(self._facts(gid, moves, prev_cands, prev_eval, eval_stm, loss, mover))
            pick = cands[0]
            if len(cands) > 1 and self.rng.random() < noise:
                pick = self.rng.choice(cands[1:])
            prev_eval, prev_cands = eval_stm, cands
            board.push_usi(pick.usi)
            moves.append(pick.usi)
        self.stats["games"] += 1
        return moments[: self.args.per_game]

    def _facts(self, gid, moves, prev_cands, eval_before_stm, eval_after_stm, loss, mover) -> dict:
        b = cshogi.Board()
        for u in moves[:-1]:
            b.push_usi(u)
        mark = "▲" if mover == cshogi.BLACK else "△"
        played = moves[-1]
        prev_usi = moves[-2] if len(moves) >= 2 else None
        played_kif = kif_text(b, played, prev_usi)
        captured = captured_name(b, played)
        best = prev_cands[0] if prev_cands else None
        pv_kif, best_kif = [], None
        if best:
            pb = cshogi.Board(b.sfen())
            p_prev = prev_usi
            for u in (best.pv or (best.usi,))[:4]:
                try:
                    pv_kif.append(kif_text(pb, u, p_prev))
                    pb.push_usi(u)
                    p_prev = u
                except Exception:  # noqa: BLE001
                    break
            best_kif = pv_kif[0] if pv_kif else None
        sign = 1 if mover == cshogi.BLACK else -1
        before_black = sign * eval_before_stm
        after_black = sign * -eval_after_stm
        mate_line = None
        for c in prev_cands[:1]:
            if c.mate_in:
                mate_line = f"{'指した側' if c.mate_in > 0 else '相手'}に{abs(c.mate_in)}手詰みの筋"
        ply = len(moves)
        def verdict(v: int) -> str:
            v = sign * v
            return "互角" if abs(v) < 300 else ("有利" if v > 0 else "不利") + ("（大差）" if abs(v) >= 1500 else "")
        lines = [f"手番: {mark}{SIDE_LABEL[mover]} {ply}手目",
                 f"指した側から見た形勢: {verdict(before_black)} → {verdict(after_black)}",
                 f"形勢(先手から): {before_black:+d} → {after_black:+d}" + (f"（悪手、損失{loss}）" if loss >= 150 else ""),
                 f"指した手: {mark}{played_kif}" + ("（最善手と同じ）" if best and best.usi == played else ""),
                 f"最善手: {mark}{best_kif}" + (f" / 読み筋: {' '.join(pv_kif)}" if len(pv_kif) > 1 else "") if best_kif else "最善手: 不明",
                 f"指した手で取った相手の駒: {captured or 'なし'}", f"局面: {phase(ply)}"]
        if mate_line:
            lines.append(f"詰み: {mate_line}")
        allowed = {played_kif, *pv_kif}
        return {"id": f"g{gid}-p{ply}", "ply": ply, "sfen_before": b.sfen(), "played": played, "loss": loss,
                "eval_before_black": before_black, "eval_after_black": after_black, "facts": "\n".join(lines),
                "allowed_moves": sorted(allowed)}

    # ---- 2. 生成と検証
    async def generate(self, m: dict) -> dict:
        msgs = [{"role": "user", "content": "【事実】\n" + FEWSHOT_FACTS},
                {"role": "assistant", "content": json.dumps(FEWSHOT_OUT, ensure_ascii=False)},
                {"role": "user", "content": "【事実】\n" + m["facts"]}]
        out = await self.llm.chat_json(SYSTEM, msgs, SCHEMA, temperature=0.6, num_predict=self.args.num_predict,
                                         repeat_penalty=1.0)
        self.stats["generated"] += 1
        if out is None:
            self.stats["llm_fail"] += 1
            return {**m, "ok": False, "errors": [f"llm: {self.llm.last_error}"]}
        errors = validate(out, m)
        if not errors:
            self.stats["valid"] += 1
        return {**m, "out": out, "ok": not errors, "errors": errors, "model": self.args.model,
                "latency": round(self.llm.last_latency or 0, 1)}

    async def run(self) -> None:
        keep_awake(True)
        try:
            await self.engine.start()
            if not await self.llm.available():
                raise SystemExit(f"model not available: {self.args.model}")
            gid = int(time.time())
            while not self.done():
                gid += 1
                moments = await self.play_and_extract(gid)
                for m in moments:
                    if self.done():
                        break
                    self.stats["moments"] += 1
                    rec = await self.generate(m)
                    with open(DATA / "candidates.jsonl", "a", encoding="utf-8") as f:
                        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    if rec["ok"]:
                        with open(DATA / "classifier_commentary.jsonl", "a", encoding="utf-8") as f:
                            for t in rec["out"]["taunts"]:
                                f.write(json.dumps({"text": t["text"], "kind": t["kind"], "src": rec["id"]},
                                                   ensure_ascii=False) + "\n")
                    self.log(f"{rec['id']} ok={rec['ok']} {rec.get('latency')}s {rec['errors'][:2]}")
                self.log(f"stats {self.stats}")
        finally:
            self.engine.quit()
            keep_awake(False)


def validate(out: dict, m: dict) -> list[str]:
    errs = []
    c = out.get("commentary", "")
    if not 30 <= len(c) <= 160:
        errs.append(f"commentary length {len(c)}")
    allowed = {re.sub(r"\s", "", a) for a in m["allowed_moves"]}
    texts = [c] + [t.get("text", "") for t in out.get("taunts", [])] + [out.get("gunshi", {}).get("text", "")]
    for t in texts:
        for mv in MOVE_RE.findall(t):
            norm = re.sub(r"\s", "", mv).translate(str.maketrans("123456789", "１２３４５６７８９")).replace("王", "玉").replace("竜", "龍")
            if norm.startswith("同"):
                continue
            if not any(norm == a or a.startswith(norm) or norm.startswith(a) for a in allowed):
                errs.append(f"unknown move {mv}")
    taunts = out.get("taunts", [])
    if len(taunts) != 3:
        errs.append(f"taunts {len(taunts)}")
    for t in taunts:
        if not 6 <= len(t.get("text", "")) <= 45:
            errs.append(f"taunt length {len(t.get('text', ''))}")
        if re.search(r"[A-Za-z]{3,}", t.get("text", "")):
            errs.append("latin in taunt")
    if any(re.search(r'[{}\[\]"]', t) for t in texts):
        errs.append("json debris in text")
    g = out.get("gunshi", {}).get("text", "")
    if not 6 <= len(g) <= 50:
        errs.append(f"gunshi length {len(g)}")
    return errs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=3)
    ap.add_argument("--max-moments", type=int, default=0)
    ap.add_argument("--model", default="gpt-oss:20b")
    ap.add_argument("--movetime", type=int, default=150)
    ap.add_argument("--per-game", type=int, default=6)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--num-predict", type=int, default=1500)
    ap.add_argument("--llm-timeout", type=float, default=180)
    ap.add_argument("--seed", type=int, default=0)
    asyncio.run(CommentaryForge(ap.parse_args()).run())


if __name__ == "__main__":
    main()
