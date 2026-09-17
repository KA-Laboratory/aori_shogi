"""口調の揺れの評価: 同じ入力で、口調制御なし/ありの崩れ率を比べる。
uv run python tools/tone_eval.py [回数/条件]   → data/tone_eval.json と標準出力
"""
import asyncio
import json
import sys
import time
from pathlib import Path

from aori_lab import dialogue as dlg
from aori_lab.lines import LineLibrary
from aori_lab.llm import OllamaClient

UTTER = [
    ("smalltalk", "今日犬の散歩一回だけど疲れた"), ("smalltalk", "柴犬で、名前はコタロウ"), ("smalltalk", "仕事で上司に怒られた"),
    ("smalltalk", "最近彼女ができたんだ"), ("smalltalk", "風邪ひいて喉が痛い"), ("smalltalk", "晩ごはんはカレーだった"),
    ("taunt_hit", "今の手、悪手でしょ"), ("taunt_miss", "その角タダじゃない？"), ("praised", "さすが天才！"),
    ("chat", "ねえ、あなたってAIなの？"),
]
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]
FACTS = {"composed": "[事実] 30手目。形勢=互角。気分=平静", "smug": "[事実] 50手目。形勢=優勢（+800）。気分=ドヤ顔",
         "rattled": "[事実] 40手目。形勢=劣勢（-400）。気分=動揺", "meltdown": "[事実] 70手目。形勢=大差で劣勢（-2000）。気分=大混乱",
         "coverUp": "[事実] 35手目。私の直前の手は悪手だった。気分=取り繕い"}


async def run(tone: bool, temp: float, reps: int, llm, lines) -> dict:
    res = {"calls": 0, "raw_bad": 0, "final_bad": 0, "fallback": 0, "attempts": 0, "sec": 0.0, "samples": []}
    for r in range(reps):
        for mood in MOODS:
            for trig, text in UTTER:
                ex = lines.lines_for(mood, trig)[:5]
                st: dict = {}
                t = time.monotonic()
                rep = await dlg.compose_reply(llm, FACTS[mood], f"相手の発言「{text}」にキャラらしく返す。雑談なら共感して質問を1つ。",
                                              [dlg.ActionOption("none", "返事をするだけ")],
                                              [{"role": "user", "content": f"[相手の発言] {text}"}], ex, mood=mood,
                                              tone_control=tone, stats=st, temperature=temp)
                res["sec"] += time.monotonic() - t
                res["calls"] += 1
                raws = st.get("raw", [])
                res["attempts"] += len(raws)
                if raws and dlg.TONE.violations(raws[0], mood):
                    res["raw_bad"] += 1
                if rep is None:
                    res["fallback"] += 1
                elif dlg.TONE.violations(rep.speech, mood):
                    res["final_bad"] += 1
                if len(res["samples"]) < 60:
                    res["samples"].append({"mood": mood, "in": text, "raw": raws[:1], "out": rep.speech if rep else None})
    return res


async def main():
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    llm = OllamaClient()
    lines = LineLibrary.load()
    out = {"model": llm.model}
    if len(sys.argv) > 2:
        llm.model = sys.argv[2]
    out["model"] = llm.model
    for tone, temp in ((False, 0.95), (True, 0.95), (True, 0.7)):
        r = await run(tone, temp, reps, llm, lines)
        n = r["calls"]
        print(f"tone_control={tone} temp={temp}: calls {n} raw崩れ {r['raw_bad']/n:.0%} 最終崩れ {r['final_bad']/n:.0%} "
              f"作り直し平均 {r['attempts']/n:.2f} テンプレ落ち {r['fallback']/n:.0%} 平均 {r['sec']/n:.1f}s", flush=True)
        out[f"tone_{tone}_{temp}"] = r
    Path(f"data/tone_eval_{llm.model.replace(':', '_')}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")


asyncio.run(main())
