"""やねうら王（USI、サブプロセス）クライアント。スレッドで読み、asyncio から使う。"""
from __future__ import annotations

import asyncio
import os
import queue
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path

from .usi import Candidate, CandidateCollector, parse_info

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = ROOT / "engine" / "YaneuraOu_NNUE_halfkp_256x2_32_32-V900Git_AVX2.exe"
DEFAULT_EVAL_DIR = ROOT / "engine" / "eval"

# 解析用の評価関数（PC 上の研究用。アプリには同梱しない）
ENGINE_PRESETS = {
    "hao": {"exe": DEFAULT_ENGINE, "eval_dir": DEFAULT_EVAL_DIR, "fv_scale": 20},  # tanuki- Háo, GPLv3
    "aoba": {"exe": ROOT / "engine" / "dl" / "aoba" / "AobaNNUE" / "AobaNNUE_AVX2.exe",
             "eval_dir": ROOT / "engine" / "dl" / "aoba" / "AobaNNUE" / "eval", "fv_scale": 40},  # AobaNNUE, GPLv3
    "suisho5": {"exe": DEFAULT_ENGINE, "eval_dir": ROOT / "engine" / "dl" / "suisho5", "fv_scale": 24},  # 水匠5
}


def engine_from_preset(name: str, threads: int | None = None) -> "UsiEngine":
    p = ENGINE_PRESETS[name]
    e = UsiEngine(exe=p["exe"], eval_dir=p["eval_dir"], threads=threads, fv_scale=p["fv_scale"])
    e.name = name
    return e


@dataclass
class SearchResult:
    bestmove: str
    candidates: list[Candidate]
    depth: int | None


class UsiEngine:
    def __init__(self, exe: Path = DEFAULT_ENGINE, eval_dir: Path = DEFAULT_EVAL_DIR,
                 threads: int | None = None, hash_mb: int = 256, fv_scale: int = 20) -> None:
        self.exe = Path(exe)
        self.eval_dir = Path(eval_dir)
        self.threads = threads or max(1, min(4, (os.cpu_count() or 2) // 2))
        self.hash_mb = hash_mb
        self.fv_scale = fv_scale
        self._proc: subprocess.Popen | None = None
        self._lines: queue.Queue[str] = queue.Queue()
        self._lock = asyncio.Lock()
        self._multipv = 1
        self.name = "hao"

    # ---- 低レベル
    def _send(self, line: str) -> None:
        assert self._proc and self._proc.stdin
        self._proc.stdin.write(line + "\n")
        self._proc.stdin.flush()

    def _reader(self) -> None:
        assert self._proc and self._proc.stdout
        for raw in self._proc.stdout:
            self._lines.put(raw.rstrip("\r\n"))
        self._lines.put("__EOF__")

    def _wait_for(self, pred, timeout: float) -> str:
        import time
        end = time.monotonic() + timeout
        while True:
            remain = end - time.monotonic()
            if remain <= 0:
                raise TimeoutError("engine timeout")
            line = self._lines.get(timeout=remain)
            if line == "__EOF__":
                raise RuntimeError("engine exited")
            if pred(line):
                return line

    # ---- 起動
    def start_sync(self) -> None:
        if self._proc:
            return
        if not self.exe.exists():
            raise FileNotFoundError(f"engine not found: {self.exe}（python/tools/setup_engine.ps1 を実行）")
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        self._proc = subprocess.Popen([str(self.exe)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL, text=True, encoding="utf-8",
                                      cwd=str(self.exe.parent), creationflags=flags)
        threading.Thread(target=self._reader, daemon=True).start()
        self._send("usi")
        self._wait_for(lambda l: l == "usiok", 10)
        for opt in [f"EvalDir value {self.eval_dir}", f"FV_SCALE value {self.fv_scale}",
                    f"Threads value {self.threads}", f"USI_Hash value {self.hash_mb}",
                    "BookFile value no_book", "NetworkDelay value 0", "NetworkDelay2 value 0",
                    "MinimumThinkingTime value 100", "RoundUpToFullSecond value false", "MultiPV value 1"]:
            self._send(f"setoption name {opt}")
        self._send("isready")
        self._wait_for(lambda l: l == "readyok", 60)
        self._send("usinewgame")

    def think_sync(self, sfen: str, moves: list[str], movetime_ms: int, multipv: int = 1) -> SearchResult:
        if multipv != self._multipv:
            self._send(f"setoption name MultiPV value {multipv}")
            self._multipv = multipv
        pos = f"position sfen {sfen}" + (f" moves {' '.join(moves)}" if moves else "")
        # 前の出力の残りを捨てる
        while not self._lines.empty():
            self._lines.get_nowait()
        self._send(pos)
        self._send(f"go movetime {movetime_ms}")
        col = CandidateCollector()
        while True:
            line = self._wait_for(lambda l: True, movetime_ms / 1000 + 10)
            if line.startswith("bestmove"):
                best = line.split()[1]
                return SearchResult(best, col.candidates, col.depth)
            info = parse_info(line)
            if info:
                col.add(info)

    def quit(self) -> None:
        if self._proc:
            try:
                self._send("quit")
            except Exception:
                pass
            self._proc = None

    # ---- async
    async def start(self) -> None:
        await asyncio.to_thread(self.start_sync)

    async def think(self, sfen: str, moves: list[str], movetime_ms: int, multipv: int = 1) -> SearchResult:
        async with self._lock:
            return await asyncio.to_thread(self.think_sync, sfen, moves, movetime_ms, multipv)
