"""解析エンジン（hao / aoba / suisho5）が起動し、初期局面を読めるか確認。uv run python tools/check_engines.py"""
from aori_lab.engine import ENGINE_PRESETS, engine_from_preset

SFEN = "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"
for name in ENGINE_PRESETS:
    e = engine_from_preset(name, threads=2)
    try:
        e.start_sync()
        r = e.think_sync(SFEN, [], 500, multipv=3)
        print(name, "best", r.bestmove, "depth", r.depth, [(c.usi, c.score_cp) for c in r.candidates[:3]])
    except Exception as ex:  # noqa: BLE001
        print(name, "FAILED", ex)
    finally:
        e.quit()
