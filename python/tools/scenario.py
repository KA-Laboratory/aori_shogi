"""起動中のサーバに対話シナリオを流し、結果を UTF-8 で書き出す（動作確認用）。

uv run python tools/scenario.py out.txt "7g7f" "chat:その角タダじゃない？" "offer:accept" ...
"""
import json
import sys
import time

import httpx

BASE = "http://127.0.0.1:8765"


def main():
    out = open(sys.argv[1], "w", encoding="utf-8")
    c = httpx.Client(timeout=180)
    seen = 0

    def dump(s, label):
        nonlocal seen
        out.write(f"\n=== {label}  mood={s['mood_label']} stance={s['stance_label']} eval={s['eval_ai']} "
                  f"c={s['mind']['composure']:.2f} h={s['mind']['hubris']:.2f} p={s['mind']['panic']:.2f} "
                  f"pending={s['pending']} latency={s['llm']['latency']}\n")
        for m in s["chat"][seen:]:
            out.write(f"  [{m['role']}] {m['text']}" + (f"  <{m.get('action')}/{m.get('source')}>" if m['role'] == 'gunshi' else "") + "\n")
        seen = len(s["chat"])
        out.write(f"  kif: {' '.join(s['kif'][-6:])}\n")
        out.flush()

    s = c.get(f"{BASE}/api/state").json()
    dump(s, "state")
    for step in sys.argv[2:]:
        t = time.time()
        if step.startswith("chat:"):
            r = c.post(f"{BASE}/api/chat", json={"text": step[5:]})
        elif step.startswith("offer:"):
            r = c.post(f"{BASE}/api/offer", json={"accept": step[6:] == "accept"})
        elif step.startswith("debug:"):
            r = c.post(f"{BASE}/api/debug/offer", json={"kind": step[6:]})
        elif step.startswith("new:"):
            r = c.post(f"{BASE}/api/new", json={"ai_side": step[4:]}); seen = 0
        elif step == "best":
            # 局面の合法手のうち先頭を指す（テスト用）
            st = c.get(f"{BASE}/api/state").json()
            r = c.post(f"{BASE}/api/move", json={"usi": st["legal"][0]})
        else:
            r = c.post(f"{BASE}/api/move", json={"usi": step})
        if r.status_code != 200:
            out.write(f"\n!!! {step}: {r.status_code} {r.text}\n")
            continue
        dump(r.json(), f"{step} ({time.time()-t:.1f}s)")
    out.close()


if __name__ == "__main__":
    main()
