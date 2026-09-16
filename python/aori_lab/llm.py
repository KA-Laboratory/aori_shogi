"""Ollama クライアント（JSON スキーマ付きの構造化出力）。"""
from __future__ import annotations

import json
import os
import time

import httpx

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
CHAT_MODEL = os.environ.get("AORI_CHAT_MODEL", "qwen3:8b")
JUDGE_MODEL = os.environ.get("AORI_JUDGE_MODEL", "gpt-oss:20b")


class OllamaClient:
    def __init__(self, model: str = CHAT_MODEL, host: str = OLLAMA_HOST, timeout: float = 60.0) -> None:
        self.model = model
        self.host = host.rstrip("/")
        self.timeout = timeout
        self.last_latency: float | None = None
        self.last_error: str | None = None

    async def available(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=3) as c:
                r = await c.get(f"{self.host}/api/tags")
                names = [m["name"] for m in r.json().get("models", [])]
                return any(n == self.model or n.startswith(self.model + ":") for n in names)
        except Exception as e:  # noqa: BLE001
            self.last_error = str(e)
            return False

    async def chat_json(self, system: str, messages: list[dict], schema: dict,
                        temperature: float = 0.8, num_predict: int = 256) -> dict | None:
        body = {
            "model": self.model,
            "stream": False,
            "think": False,
            "format": schema,
            "keep_alive": "30m",
            "options": {"temperature": temperature, "num_ctx": 4096, "num_predict": num_predict,
                        "repeat_penalty": 1.15, "top_p": 0.95},
            "messages": [{"role": "system", "content": system}, *messages],
        }
        t = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as c:
                r = await c.post(f"{self.host}/api/chat", json=body)
                r.raise_for_status()
                content = r.json()["message"]["content"]
            self.last_latency = time.monotonic() - t
            return json.loads(content)
        except Exception as e:  # noqa: BLE001
            self.last_latency = time.monotonic() - t
            self.last_error = f"{type(e).__name__}: {e}"
            return None
