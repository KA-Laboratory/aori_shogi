"""ローカル Web サーバ: ブラウザで軍師と対局・対話する。

起動: cd python && uv run python -m aori_lab.server  →  http://127.0.0.1:8765
"""
from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

import cshogi
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .engine import UsiEngine
from .lines import LineLibrary
from .llm import OllamaClient
from .session import Session

STATIC = Path(__file__).parent / "static"
S: dict[str, Session] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    engine = UsiEngine()
    await engine.start()
    llm = OllamaClient()
    if not await llm.available() or os.environ.get("AORI_NO_LLM"):
        print(f"[aori] LLM {llm.model} を使えません（テンプレートのみで動作）: {llm.last_error}")
        llm = None
    else:
        print(f"[aori] LLM: {llm.model}")
    sess = Session(engine=engine, llm=llm, lines=LineLibrary.load())
    S["main"] = sess
    await sess.new_game(cshogi.WHITE)
    yield
    engine.quit()


app = FastAPI(lifespan=lifespan)


def sess() -> Session:
    return S["main"]


class NewGame(BaseModel):
    ai_side: str = "white"


class MoveReq(BaseModel):
    usi: str


class ChatReq(BaseModel):
    text: str


class OfferReq(BaseModel):
    accept: bool


@app.get("/")
async def index():
    return FileResponse(STATIC / "index.html")


@app.get("/api/state")
async def state():
    return sess().state()


async def _run(coro):
    s = sess()
    if s.lock.locked():
        coro.close()
        raise HTTPException(409, "処理中です")
    async with s.lock:
        try:
            await coro
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
    return s.state()


@app.post("/api/new")
async def new_game(req: NewGame):
    return await _run(sess().new_game(cshogi.BLACK if req.ai_side == "black" else cshogi.WHITE))


@app.post("/api/move")
async def move(req: MoveReq):
    return await _run(sess().player_move(req.usi))


@app.post("/api/chat")
async def chat(req: ChatReq):
    return await _run(sess().player_chat(req.text))


@app.post("/api/offer")
async def offer(req: OfferReq):
    return await _run(sess().respond_offer(req.accept))


@app.get("/api/memory")
async def memory():
    return {"facts": [f.__dict__ for f in sess().memory.facts]}


@app.delete("/api/memory/{fact_id}")
async def memory_delete(fact_id: str):
    if not sess().memory.delete(fact_id):
        raise HTTPException(404, "not found")
    return sess().state()


@app.delete("/api/memory")
async def memory_clear():
    sess().memory.clear()
    return sess().state()


class DebugOffer(BaseModel):
    kind: str


@app.post("/api/debug/offer")
async def debug_offer(req: DebugOffer):
    return await _run(sess().debug_offer(req.kind))


def main() -> None:
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("AORI_PORT", "8765")))


if __name__ == "__main__":
    main()
