"""1回分の生成を素のまま見る（空返しの原因調べ用）。"""
import json
import time

import httpx

from aori_lab.learn import finetune_gen as g

for count in (5, 3):
    body = {"model": "gpt-oss:20b", "stream": False, "format": g.SCHEMA, "keep_alive": "30m", "think": "low",
            "options": {"temperature": 0.9, "num_ctx": 8192, "num_predict": 1500 + 160 * count},
            "messages": [{"role": "system", "content": g.system_prompt()},
                         {"role": "user", "content": g.batch_prompt("move", "smug", count, [])}]}
    t = time.time()
    d = httpx.post("http://localhost:11434/api/chat", json=body, timeout=1800).json()
    m = d.get("message", {})
    print(f"count={count} sec={time.time() - t:.0f} done={d.get('done_reason')} eval={d.get('eval_count')} "
          f"think={len(m.get('thinking') or '')} content={len(m.get('content') or '')}", flush=True)
    print("content:", (m.get("content") or "")[:400], flush=True)
    try:
        print("items:", len(json.loads(m.get("content") or "{}").get("items", [])), flush=True)
    except Exception as e:  # noqa: BLE001
        print("parse err", e, flush=True)
