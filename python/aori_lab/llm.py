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
                        temperature: float = 0.8, num_predict: int = 256,
                        repeat_penalty: float = 1.15) -> dict | None:
        body = {
            "model": self.model,
            "stream": False,
            "think": "low" if self.model.startswith("gpt-oss") else False,
            "format": schema,
            "keep_alive": "30m",
            "options": {"temperature": temperature, "num_ctx": 4096, "num_predict": num_predict,
                        "repeat_penalty": repeat_penalty, "top_p": 0.95},
            "messages": [{"role": "system", "content": system}, *messages],
        }
        if self.model.startswith("gpt-oss"):
            # 推論トークンも num_predict を消費するので、出力が空にならないよう余裕を持たせる
            body["options"]["num_predict"] = max(1500, num_predict * 4)
            body["options"]["num_ctx"] = 8192
        t = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as c:
                r = await c.post(f"{self.host}/api/chat", json=body)
                r.raise_for_status()
                msg = r.json()["message"]
                content = msg.get("content") or ""
            self.last_latency = time.monotonic() - t
            if not content.strip():
                self.last_error = f"empty content (thinking {len(msg.get('thinking') or '')} chars)"
                return None
            return json.loads(content)
        except Exception as e:  # noqa: BLE001
            self.last_latency = time.monotonic() - t
            self.last_error = f"{type(e).__name__}: {e}"
            return None
