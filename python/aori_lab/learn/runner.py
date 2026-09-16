"""夜通し回す学習ループ。

uv run python -m aori_lab.learn.runner --hours 8
  --gen-model / --judge-model（既定 gpt-oss:20b。遅すぎれば qwen3:8b に自動で切替）
出力: data/learn/{pool.json, events.jsonl, games.jsonl, report.md, candidates/}
"""
from __future__ import annotations

import argparse
import asyncio
import ctypes
import os
import random
import signal
import time
from pathlib import Path

from ..engine import UsiEngine
from ..llm import OllamaClient
from .arena import Arena, ArenaConfig
from .forge import generate, judge, seed_pool
from .pool import KINDS, TauntPool
from .report import export_candidates, write_report

DATA = Path(__file__).resolve().parents[2] / "data" / "learn"


def keep_awake(on: bool) -> None:
    """実行中だけスリープを抑止（Windows）。終了すると元に戻る。"""
    if os.name != "nt":
        return
    ES_CONTINUOUS, ES_SYSTEM_REQUIRED = 0x80000000, 0x00000001
    ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS | (ES_SYSTEM_REQUIRED if on else 0))


class Runner:
    def __init__(self, args) -> None:
        self.args = args
        self.deadline = time.time() + args.hours * 3600
        self.stop = asyncio.Event()
        self.pool = TauntPool(DATA / "pool.json")
        self.rng = random.Random(args.seed)
        self.engine = UsiEngine(threads=args.threads, hash_mb=64)
        self.gen = OllamaClient(model=args.gen_model, timeout=args.llm_timeout)
        self.judge = OllamaClient(model=args.judge_model, timeout=args.llm_timeout)
        self.counters = {"generated": 0, "judged": 0, "judge_fail": 0, "gen_fail": 0, "games": 0}
        self.latencies: list[float] = []
        self.pool_lock = asyncio.Lock()

    def log(self, msg: str) -> None:
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line, flush=True)
        with (DATA / "runner.log").open("a", encoding="utf-8") as f:
            f.write(line + "\n")

    def done(self) -> bool:
        if (DATA / "STOP").exists():
            self.stop.set()
        return self.stop.is_set() or time.time() >= self.deadline

    async def save(self) -> None:
        async with self.pool_lock:
            self.pool.save()

    async def arena_loop(self) -> None:
        arena = Arena(self.engine, self.pool, ArenaConfig(movetime_ms=self.args.movetime, observe_ms=self.args.movetime,
                                                          events_path=DATA / "events.jsonl", games_path=DATA / "games.jsonl"),
                      seed=self.args.seed)
        gp = DATA / "games.jsonl"
        if gp.exists():
            arena.stats.games = sum(1 for _ in gp.open(encoding="utf-8"))
        while not self.done():
            if len(self.pool.usable()) < 5:
                await asyncio.sleep(10)
                continue
            try:
                rec = await arena.play_game()
                self.counters["games"] += 1
                self.log(f"game {rec['game']} {'CTRL' if rec['control'] else 'TAUNT'} taunter_won={rec['taunter_won']} "
                         f"reason={rec['reason']} plies={rec['plies']} taunts={rec['taunts']} loss={rec['gunshi_avg_loss']:.0f}")
                if self.counters["games"] % 5 == 0:
                    await self.save()
            except Exception as e:  # noqa: BLE001
                self.log(f"arena error: {type(e).__name__}: {e}")
                await asyncio.sleep(5)
                try:
                    self.engine.quit()
                    self.engine = UsiEngine(threads=self.args.threads, hash_mb=64)
                    await self.engine.start()
                    arena.engine = self.engine
                except Exception as e2:  # noqa: BLE001
                    self.log(f"engine restart failed: {e2}")
                    await asyncio.sleep(30)

    async def forge_loop(self) -> None:
        fails = 0
        while not self.done():
            unj = self.pool.unjudged()
            try:
                if unj:
                    e = unj[0]
                    t = time.time()
                    j = await judge(self.judge, e)
                    dt = time.time() - t
                    if j is None:
                        self.counters["judge_fail"] += 1
                        fails += 1
                        self.log(f"judge fail ({dt:.0f}s): {self.judge.last_error}")
                        self.latencies.append(dt if dt > 1 else 0)
                        self.maybe_switch_model(dt)
                        if fails >= 3:
                            self.pool.entries.pop(e.id, None)
                            fails = 0
                        await asyncio.sleep(3)
                        continue
                    fails = 0
                    e.judgement = j
                    self.latencies.append(dt)
                    self.counters["judged"] += 1
                    self.log(f"judged {dt:.0f}s [{j.kind} true{j.sting_if_true}/false{j.sting_if_false}/bf{j.backfire}"
                             f"{'' if j.appropriate else ' NG'}] {e.text}")
                    self.maybe_switch_model(dt)
                    if self.counters["judged"] % 5 == 0:
                        await self.save()
                else:
                    counts = {k: len(self.pool.usable(k)) for k in KINDS}
                    kind = min(KINDS, key=lambda k: counts[k] + self.rng.random() * 8)
                    t = time.time()
                    new = await generate(self.gen, kind, self.args.batch, self.pool, self.rng)
                    added = sum(self.pool.add(x) for x in new)
                    self.counters["generated"] += added
                    if not new:
                        self.counters["gen_fail"] += 1
                        self.log(f"generate fail ({time.time()-t:.0f}s): {self.gen.last_error}")
                        await asyncio.sleep(5)
                    else:
                        self.log(f"generated {added}/{len(new)} {kind} ({time.time()-t:.0f}s)")
            except Exception as e:  # noqa: BLE001
                self.log(f"forge error: {type(e).__name__}: {e}")
                await asyncio.sleep(10)

    async def probe_primary_loop(self) -> None:
        """切替後、30分ごとに本来のモデルを試し、速くなっていれば戻す（夜にPCが空いた場合など）。"""
        while not self.done():
            for _ in range(360):
                if self.done():
                    return
                await asyncio.sleep(5)
            if self.judge.model == self.args.judge_model:
                continue
            probe = OllamaClient(model=self.args.judge_model, timeout=120)
            t = time.time()
            out = await probe.chat_json("JSONで返す", [{"role": "user", "content": "okとだけ"}],
                                        {"type": "object", "properties": {"ok": {"type": "string"}}, "required": ["ok"]},
                                        num_predict=40)
            dt = time.time() - t
            self.log(f"probe {self.args.judge_model}: {dt:.0f}s {'ok' if out else probe.last_error}")
            if out and dt < 25:
                self.judge = OllamaClient(model=self.args.judge_model, timeout=self.args.llm_timeout)
                self.gen = OllamaClient(model=self.args.gen_model, timeout=self.args.llm_timeout)
                self.latencies.clear()
                self.log(f"→ {self.args.judge_model} に戻した")

    def maybe_switch_model(self, dt: float) -> None:
        recent = self.latencies[-5:]
        if (self.args.auto_fallback and len(recent) >= 3 and sum(recent) / len(recent) > self.args.max_judge_seconds
                and self.judge.model != self.args.fallback_model):
            self.log(f"judge too slow ({sum(recent)/len(recent):.0f}s) → {self.args.fallback_model} に切替")
            self.judge = OllamaClient(model=self.args.fallback_model, timeout=self.args.llm_timeout)
            self.gen = OllamaClient(model=self.args.fallback_model, timeout=self.args.llm_timeout)
            self.latencies.clear()

    async def report_loop(self) -> None:
        while not self.done():
            for _ in range(int(self.args.report_minutes * 60 / 5)):
                if self.done():
                    break
                await asyncio.sleep(5)
            await self.write_outputs()

    async def write_outputs(self) -> None:
        await self.save()
        extra = {"経過": f"{(time.time() - self.started)/3600:.2f} 時間", "プール": len(self.pool.entries),
                 "採点済み": len(self.pool.usable()), **self.counters,
                 "採点モデル": self.judge.model,
                 "採点平均秒": f"{sum(self.latencies)/len(self.latencies):.1f}" if self.latencies else "-"}
        write_report(self.pool, DATA, extra)
        ex = export_candidates(self.pool, DATA / "candidates")
        self.log(f"report written: {ex}")

    async def run(self) -> None:
        DATA.mkdir(parents=True, exist_ok=True)
        self.started = time.time()
        n = seed_pool(self.pool)
        self.log(f"start: hours={self.args.hours} gen={self.gen.model} judge={self.judge.model} seeds+={n} pool={len(self.pool.entries)}")
        await self.engine.start()
        keep_awake(True)
        try:
            await asyncio.gather(self.arena_loop(), self.forge_loop(), self.report_loop(), self.probe_primary_loop())
        finally:
            keep_awake(False)
            await self.write_outputs()
            self.engine.quit()
            self.log("finished")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=8)
    ap.add_argument("--gen-model", default="gpt-oss:20b")
    ap.add_argument("--judge-model", default="gpt-oss:20b")
    ap.add_argument("--fallback-model", default="qwen3:8b")
    ap.add_argument("--auto-fallback", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--max-judge-seconds", type=float, default=90)
    ap.add_argument("--llm-timeout", type=float, default=300)
    ap.add_argument("--batch", type=int, default=6)
    ap.add_argument("--movetime", type=int, default=120)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--report-minutes", type=float, default=15)
    ap.add_argument("--seed", type=int, default=int(time.time()))
    args = ap.parse_args()
    r = Runner(args)
    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(r.run())
    except KeyboardInterrupt:
        r.stop.set()


if __name__ == "__main__":
    main()
