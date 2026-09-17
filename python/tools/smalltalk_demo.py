"""雑談＋記憶の動作確認（実エンジン＋Ollama）。uv run python tools/smalltalk_demo.py
記憶は data/memory/demo_memory.json（本番の記憶とは別）に保存する。"""
import asyncio
from pathlib import Path

import cshogi

from aori_lab.engine import UsiEngine
from aori_lab.lines import LineLibrary
from aori_lab.llm import OllamaClient
from aori_lab.session import Session
from aori_lab.smalltalk import MemoryStore

LINES1 = ["今日犬の散歩一回だけど疲れた", "柴犬で、名前はコタロウ。もう8歳", "ねえ、あなたってAIなの？", "その角タダじゃない？"]
LINES2 = ["ただいま〜", "コタロウ、今日は雨で散歩行けなくて拗ねてる"]


async def main():
    mem_path = Path("data/memory/demo_memory.json")
    if mem_path.exists():
        mem_path.unlink()
    eng = UsiEngine()
    await eng.start()
    llm = OllamaClient()
    s = Session(engine=eng, llm=llm, lines=LineLibrary.load(), memory=MemoryStore(mem_path), base_movetime_ms=200)

    async def talk(t):
        n = len(s.chat)
        await s.player_chat(t)
        print(f"相手: {t}")
        for c in s.chat[n + 1:]:
            print(f"  {c['role']}: {c['text']}")

    await s.new_game(cshogi.WHITE)
    print("軍師:", s.chat[-1]["text"])
    await s.player_move("7g7f")
    for t in LINES1:
        await talk(t)
    print("記憶:", [(f.key, f.value) for f in s.memory.facts])
    print("===== 次の対局 =====")
    await s.new_game(cshogi.WHITE)
    print("軍師:", s.chat[-1]["text"])
    for t in LINES2:
        await talk(t)
    print("記憶:", [(f.key, f.value, f.mentions) for f in s.memory.facts])
    eng.quit()


asyncio.run(main())
