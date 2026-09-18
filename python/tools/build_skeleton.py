"""賢太郎さんが「セリフだけ」書けるように、場面ごとの雛形を作る。

uv run python tools/build_skeleton.py
→ data/finetune_gen_edit/skeleton.jsonl（line が空の行。facts と player は埋めてある）

facts の出どころ:
- 盤面の場面（move / taunt_hit / blunder_self など）は、実際の自己対局から取った局面（data/learn_commentary/moments.jsonl）。
  手数・評価値・損失・指した手はエンジンが出した本物の数字なので、ありえない値にならない。
- 相手の発言は、これまでのモデル生成（qwen3 / gpt-oss、Apache 2.0）から拾ったもの。
目標件数から、すでに書けている分（edited_by_owner.jsonl）を引いた数だけ作る。
"""
from __future__ import annotations

import json
import random
import re
from collections import Counter, defaultdict
from pathlib import Path

from aori_lab.learn.finetune_gen import S

DATA = Path(__file__).resolve().parents[1] / "data"
EDIT = DATA / "finetune_gen_edit"
POOLS = ["finetune_gen_v1", "finetune_gen_v2", "finetune_gen_v3", "finetune_gen_v5",
         "cmp_gpt-oss_20b", "cmp_qwen3_8b"]
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]
BOARD_SCENES = {"move", "taunt_hit", "blunder_self", "blunder_opponent", "checkmate_threat",
                "checkmate_win", "checkmate_lose"}
# 盤面と関係ない場面の事実（型が決まっているものはここで作る）
FIXED_FACTS = {
    "draw": ["千日手による引き分け。", "持将棋（点数）による引き分け。", "千日手。私はまだ指したかった。",
             "持将棋による引き分け。実質私の優勢だったと主張。", "千日手。形勢は互角のままだった。"],
    "start": ["対局開始。私は後手。", "対局開始。私は先手。", "対局開始。相手は初めての挑戦者。",
              "対局開始。前局は私が負けている。", "対局開始。前局は私が勝っている。",
              "対局開始。私は先手。相手とは今日3局目。", "対局開始。私は後手。相手は連勝中。",
              "対局開始。持ち時間は10分。"],
    "win": ["相手が投了。私の勝ち。", "相手が投了。接戦だった。", "相手が投了。大差での勝ち。",
            "相手が投了。終盤で逆転した。", "相手が投了。私は途中まで劣勢だった。"],
    "lose": ["私が投了した。", "私が投了した。最後は攻め合い負け。", "私が投了した。序盤から一方的だった。",
             "私が投了した。優勢から逆転された。", "私が投了した。時間に追われた。"],
    "ai_question": ["形勢=互角（評価値+30）。相手にAIかと聞かれた。",
                    "形勢=私の優勢（評価値+700）。相手にAIかと聞かれた。",
                    "形勢=私の劣勢（評価値-700）。相手にAIかと聞かれた。",
                    "形勢=互角。相手にAIかと聞かれた（2回目）。",
                    "形勢=私の優勢。相手に中の人がいるのかと聞かれた。"],
    "abuse": ["相手の発言は不適切。形勢=互角。", "相手の発言は不適切。形勢=私の優勢。",
              "相手の発言は不適切。形勢=私の劣勢。", "相手の発言は不適切（2回目）。形勢=互角。",
              "相手の発言は不適切。私は直前に悪手を指している。"],
    "smalltalk": ["相手について覚えていること: なし。",
                  "相手について覚えていること: 犬を飼っている（名前はハチ）。",
                  "相手について覚えていること: 猫を飼っている（名前はミケ）。",
                  "相手について覚えていること: 仕事が忙しい。",
                  "相手について覚えていること: 体調が悪い（頭痛あり）。",
                  "相手について覚えていること: 週末に旅行へ行った。",
                  "相手について覚えていること: ラーメンが好き。",
                  "相手について覚えていること: 子どもがいる。",
                  "相手について覚えていること: 学生である。",
                  "相手について覚えていること: 音楽が趣味（ジャズ）。"],
}

# 相手の発言の型が決まっている場面（モデル生成の素材が無い／少ない）
FIXED_PLAYERS = {
    "checkmate_lose": ["詰みました。", "これで詰みですね。", "勝負ありですね。", "私の勝ちだ。", "詰みだね。"],
    "draw": ["引き分けですね。", "千日手ですね。", "これ、引き分けかな。", "持将棋だね。"],
    "win": ["負けました。", "参りました。", "投了します。", "負けだ、強いな。"],
}

# 不適切発言の素材はアプリ自身の語彙（tool/shogi_terms.src.json の abuse）から作る
ABUSE_FRAMES = ["{w}とか言うなよ。", "君、{w}って言ったよね？", "{w}。そんな言い方はないだろ。",
                "{w}って言われた気がするんだけど。", "さっきの{w}、ちょっと不愉快だよ。"]


def abuse_players() -> list[str]:
    p = Path(__file__).resolve().parents[2] / "tool" / "shogi_terms.src.json"
    if not p.exists():
        return []
    words = [t["t"] for t in json.loads(p.read_text(encoding="utf-8")).get("abuse", [])]
    return [f.format(w=w) for w in words for f in ABUSE_FRAMES]


def moments() -> list[dict]:
    p = DATA / "learn_commentary" / "moments.jsonl"
    out = []
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        m = json.loads(line)
        f = m.get("facts", "")
        mv = re.search(r"指した手: (\S+)", f)
        if not mv:
            continue
        move = normalize_move(mv.group(1))
        if move.lstrip("▲△").startswith("同"):
            continue  # 「同　飛」は単体だと何の手か分からないので使わない
        out.append({"ply": m["ply"], "loss": m.get("loss", 0), "move": move,
                    "best": (re.search(r"最善手: (\S+)", f) or [None, ""])[1],
                    "eval": m.get("eval_after_black", 0)})
    return out


ZEN = str.maketrans("０１２３４５６７８９", "0123456789")


def normalize_move(mv: str) -> str:
    """「△９八玉（最善手と同じ）」→「△9八玉」。注記を落とし、数字を半角に揃える。"""
    mv = re.sub(r"[（(][^）)]*[）)]", "", mv).strip()
    return mv.translate(ZEN)


def stance(ev: int) -> str:
    return "優勢" if ev >= 300 else ("劣勢" if ev <= -300 else "互角")


def board_facts(scene: str, m: dict, rng: random.Random) -> str:
    ev, loss, ply = m["eval"], m["loss"], m["ply"]
    # 軍師の手は △、相手の手は ▲ に揃える
    mv = "△" + m["move"].lstrip("▲△")
    if scene == "blunder_opponent" or scene == "checkmate_lose":
        mv = "▲" + m["move"].lstrip("▲△")
    if scene == "move":
        tail = "は最善。" if loss < 50 else f"は悪手で約{loss}点損。"
        return f"{ply}手目。形勢={stance(ev)}（評価値{ev:+}）。私の手 {mv} {tail}"
    if scene == "taunt_hit":
        return f"私の直前の手 {mv} は悪手（約{max(60, loss)}点損）。相手の煽りは図星。"
    if scene == "blunder_self":
        return f"直前の手 {mv} は悪手（約-{max(100, loss)}点損）。私は内心それに気づいている。"
    if scene == "blunder_opponent":
        return f"相手の手 {mv} は悪手（約+{max(100, loss)}点得）。"
    if scene == "checkmate_win":
        return f"私の手 {mv} で相手玉が詰み。勝利。"
    if scene == "checkmate_lose":
        return f"相手の手 {mv} で私の玉が詰み。敗北。"
    if scene == "checkmate_threat":
        return f"私の手 {mv} で詰めろがかかる。評価値+{rng.choice([1500, 2000, 2500, 3000, 4000])}。"
    return ""


def clean_player(scene: str, t: str) -> str | None:
    """モデル生成の素材から、場面に合わない・壊れている発言を落とす。"""
    t = t.strip().strip("」』「『").strip()
    if len(t) < 4 or len(t) > 40:
        return None
    if t.count("、") > 3:
        return None
    if scene == "ai_question" and not re.search(r"AI|ＡＩ|人間|ロボット|機械|中の人", t):
        return None
    if scene == "smalltalk" and re.search(r"将棋|歩|銀|飛車|詰み|評価値", t):
        return None
    return t


def pick(rng: random.Random, pool: list[str], used: set[str], fallback: str) -> str:
    """同じものが続かないように、まだ使っていないものを優先して選ぶ。"""
    if not pool:
        return fallback
    fresh = [x for x in pool if x not in used]
    got = rng.choice(fresh or pool)
    used.add(got)
    return got


def main() -> None:
    rng = random.Random(0)
    have = Counter()
    done = EDIT / "all.jsonl" if (EDIT / "all.jsonl").exists() else EDIT / "edited_by_owner.jsonl"
    if done.exists():
        for line in done.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                have[(r["scene"], r["mood"])] += 1
    # 相手の発言の素材（モデル生成）を場面ごとに集める
    players: dict[str, list[str]] = defaultdict(list)
    facts_pool: dict[str, list[str]] = defaultdict(list)
    for name in POOLS:
        p = DATA / name / "accepted.jsonl"
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("player"):
                players[r["scene"]].append(r["player"])
            f = r["facts"]
            # 場面に合わない混ざりものは素材にしない
            if r["scene"] == "smalltalk" and ("手数" in f or "評価値" in f):
                continue
            facts_pool[r["scene"]].append(f)
    for scene in list(players):
        seen: list[str] = []
        for t in players[scene]:
            c = clean_player(scene, t)
            if c and c not in seen:
                seen.append(c)
        players[scene] = seen
    for scene, fixed in FIXED_PLAYERS.items():
        players[scene] = fixed + [t for t in players.get(scene, []) if t not in fixed]
    players["abuse"] = abuse_players()
    ms = moments()
    # 詰みの手が玉なのはありえないので、詰みの場面には使わない
    # 詰みの手が玉なのはありえない。打ち歩詰めは反則、歩の一手詰めも不自然なので歩は使わない
    ms_mate = [m for m in ms if re.search(r"[金銀桂香飛角龍馬と圭杏全]", m["move"])
               and not re.search(r"[玉王歩]", m["move"])]
    rows = []
    for scene, (total, desc, fp, pp, weights) in S.items():
        per = {m: 0 for m in MOODS}
        ws = {m: weights.get(m, 1.0) for m in MOODS}
        tot = sum(ws.values())
        for m in MOODS:
            per[m] = round(total * ws[m] / tot)
        used_f: set[str] = set()
        used_p: set[str] = set()
        for mood in MOODS:
            need = max(0, per[mood] - have[(scene, mood)])
            for i in range(need):
                if scene in FIXED_FACTS:
                    facts = pick(rng, FIXED_FACTS[scene], used_f, FIXED_FACTS[scene][0])
                elif scene in BOARD_SCENES:
                    src = ms_mate if scene in {"checkmate_win", "checkmate_lose"} else ms
                    facts = board_facts(scene, rng.choice(src), rng) if src else ""
                    if not facts:
                        facts = f"（{desc}の事実をここに書く。型: {fp}）"
                else:
                    pool = facts_pool.get(scene) or []
                    facts = pick(rng, pool, used_f, f"（{desc}の事実をここに書く。型: {fp}）")
                player = ""
                if pp != "空文字":
                    player = pick(rng, players.get(scene) or [], used_p, f"（{pp}）")
                rows.append({"id": f"{scene}-{mood}-{len(rows) + 1:04d}", "scene": scene, "mood": mood,
                             "facts": facts, "player": player, "line": "", "flags": [], "keep": True,
                             "source": "skeleton"})
    EDIT.mkdir(parents=True, exist_ok=True)
    (EDIT / "skeleton.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                                         encoding="utf-8")
    c = Counter(r["scene"] for r in rows)
    print(f"{len(rows)}件 → data/finetune_gen_edit/skeleton.jsonl")
    for k in S:
        if c.get(k):
            print(f"  {k}: {c[k]}")


if __name__ == "__main__":
    main()
