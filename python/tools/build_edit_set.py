"""手直し用のひとまとめを作る: これまでの生成をぜんぶ集め、重複を消し、問題点を印にして並べる。

uv run python tools/build_edit_set.py
→ data/finetune_gen_edit/to_edit.jsonl（1行1件、scene→mood の順）と README.md
直したら: uv run python tools/check_edited.py data/finetune_gen_edit/to_edit.jsonl
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from aori_lab.learn.finetune_gen import (BAD_FACT, DEBRIS, MIN_LEN, MOOD_MARK, PERSONA_END, S, STIFF, MESS,
                                         Checker, squares)

DATA = Path(__file__).resolve().parents[1] / "data"
OUT = DATA / "finetune_gen_edit"
SOURCES = ["finetune_gen_v1", "finetune_gen_v2", "finetune_gen_v3", "finetune_gen_v4", "finetune_gen_v5",
           "cmp_gpt-oss_20b", "cmp_qwen3_8b"]
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]
# 相手の発言が無いと成立しない場面
NEEDS_PLAYER = {"taunt_hit", "taunt_miss", "praised", "praise_suspicious", "abuse", "ai_question",
                "offer_reply", "smalltalk", "slip", "question_dodge"}


def fix_facts(facts: str) -> str:
    """事実の数値だけ機械的に直す（将棋としてありえない小さな値を桁上げする）。"""
    def ev(m: re.Match) -> str:
        v = int(m.group(2))
        return f"{m.group(1)}{v * 100 if v else 50}{m.group(3)}"

    facts = re.sub(r"(評価値[±+-]?)([0-9]{1,2})([）)])", ev, facts)
    facts = re.sub(r"約([0-9]{1,2})点損", lambda m: f"約{max(60, int(m.group(1)) * 10)}点損", facts)
    return facts


# 「と」は助詞として至る所に出る（「〜といたしましょう」）。駒として数えるのは「と金」だけ。
# これを直す前は、手書き527件のうち61件がこの目安に引っかかっていた（実際は47件が助詞）。
PIECES = re.compile(r"と金|[歩香桂銀金飛角玉馬龍竜]")
# 駒の名前と同じ字を使うが駒ではない言葉
NOT_A_PIECE = re.compile(r"馬鹿|歩[くみいけんま]|一歩|角度|玉座|金輪際|金言|飛[びぶんばこ]|香[りばし]")


STANCE = re.compile(r"形勢=(優勢|互角|劣勢)（評価値([+\-−]?\d+)）")


def stance_mismatch(facts: str) -> bool:
    """事実の「形勢=」が評価値と食い違っていないか。

    app 側（game_controller.dart の _facts）は +300 以上を優勢、-300 以下を劣勢、
    その間を互角と呼ぶ。学習データが違う呼び方をしていると軍師が数字を読めなくなる
    （-1400 を「互角に持ち込むとは」と言う出力が実際に出た）。
    """
    m = STANCE.search(facts)
    if not m:
        return False
    ev = int(m.group(2).replace("−", "-").replace("+", ""))
    want = "優勢" if ev >= 300 else "劣勢" if ev <= -300 else "互角"
    return m.group(1) != want


# アプリ（game_controller.dart の _facts）が送る事実の型。ここに無い場面は見ない。
# 型から外れた事実は、本番で来ない言い方を教えることになるので弾く。
_W = "(優勢|互角|劣勢)"
APP_SHAPE = {
    "move": rf"^\d+手目。形勢={_W}（評価値[+-]\d+）。私の手 .+ (は最善。|は悪手で約\d+点損。)$",
    # praised はアプリ側で praiseStreak が 3 未満のときだけ出るので、回数は 1 か 2 しか来ない
    "praised": rf"^形勢={_W}。相手に褒められた（[12]回目）。$",
    "praise_suspicious": r"^相手に\d+回続けて褒められた。$",
    "question_dodge": rf"^形勢={_W}。相手に読みを聞かれた。教えない。$",
    "taunt_miss": r"^私の直前の手はほぼ最善。相手の煽りは外れ。$",
    "abuse": rf"^相手の発言は不適切。形勢={_W}。$",
    "start": r"^対局開始。",
    "win": r"^相手が投了。",
    "lose": r"^私が投了した。",
}


def off_app_shape(scene: str, facts: str) -> bool:
    pat = APP_SHAPE.get(scene)
    return bool(pat) and not re.match(pat, facts)


STANCE_WORD = re.compile(r"形勢=([^（(。]+)")
APP_STANCE = {"優勢", "互角", "劣勢"}


def odd_stance_word(facts: str) -> str:
    """アプリが出さない形勢の言い方が混ざっていないか。

    アプリが送るのはこの3語だけ（game_controller.dart の _facts）。1周目の
    モデル生成由来には「形勢=持ち上がり」「形勢=大きく逆転」などが混ざっていた。
    本番で来ない言葉を教え、来る言葉を教えないので、数の割に効かない。
    言い換えられるものは tools/normalize_stance.py が揃えた。残りは人が決める。
    """
    m = STANCE_WORD.search(facts)
    if not m:
        return ""
    word = m.group(1).strip()
    return "" if word in APP_STANCE else word


def flags(r: dict, chk: Checker) -> list[str]:
    line, facts, player, mood = r["line"], r["facts"], r.get("player", ""), r["mood"]
    out = []
    if len(line) < MIN_LEN:
        out.append("短い")
    if len(line) > 90:
        out.append("90字超")
    if DEBRIS.search(line):
        out.append("JSONの破片")
    if STIFF.search(line):
        out.append("文語")
    if MESS.search(line):
        out.append("句読点の乱れ")
    if BAD_FACT.search(facts):
        out.append("事実の数値が不自然")
    if stance_mismatch(facts):
        out.append("形勢と評価値が食い違い")
    odd = odd_stance_word(facts)
    if odd:
        out.append(f"アプリが出さない形勢の言い方:{odd}")
    if "評価値±" in facts:
        out.append("評価値の符号が±")
    if off_app_shape(r["scene"], facts):
        out.append("事実がアプリの型と違う")
    # 語尾の型チェックは廃止（動揺は丁寧・常体どちらでもよく、大混乱は叫びで語尾が定まらない）。
    # 口調は tone の mood_require / mood_banned が見る。
    mark = MOOD_MARK.get(mood)
    if mark and not mark.search(line):
        out.append("気分の印なし(任意)")
    v = chk.tone.violations(line, mood)
    if v:
        out.append("口調:" + ",".join(v))
    if squares(line) - squares(facts) - squares(player):
        out.append("事実にない指し手")
    # 事実が指し手を挙げているのに、別の駒の名前を出していないか（言い回しの綾もあるので任意）
    if "手 " in facts:
        plain = NOT_A_PIECE.sub("", line)
        named = set(PIECES.findall(plain)) - set(PIECES.findall(facts)) - set(PIECES.findall(player))
        if named:
            out.append("事実にない駒(任意):" + "".join(sorted(named)))
    # 相手の発言は、場面によっては有っても無くてもよい（軍師の独り言でも成立する）
    if S[r["scene"]][3] != "空文字" and not player and r["scene"] in NEEDS_PLAYER:
        out.append("player欠落")
    return out


def main() -> None:
    chk = Checker()
    rows, seen = [], set()
    for src in SOURCES:
        p = DATA / src / "accepted.jsonl"
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            key = r["line"].strip()
            if key in seen:
                continue
            seen.add(key)
            r["source"] = src
            r["facts"] = fix_facts(r["facts"])
            rows.append(r)
    scenes = list(S)
    rows.sort(key=lambda r: (scenes.index(r["scene"]), MOODS.index(r["mood"]) if r["mood"] in MOODS else 9))
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "to_edit.jsonl").open("w", encoding="utf-8") as f:
        for i, r in enumerate(rows, 1):
            f.write(json.dumps({
                "id": f"{r['scene']}-{r['mood']}-{i:04d}",
                "scene": r["scene"], "mood": r["mood"],
                "facts": r["facts"], "player": r.get("player", ""), "line": r["line"],
                "flags": flags(r, chk), "keep": True, "source": r["source"], "model": r.get("model", ""),
            }, ensure_ascii=False) + "\n")
    bad = sum(1 for r in rows if flags(r, chk))
    target = {k: v[0] for k, v in S.items()}
    have: dict[str, int] = {}
    for r in rows:
        have[r["scene"]] = have.get(r["scene"], 0) + 1
    readme = [
        "# 手直し用データ", "",
        f"{len(rows)}件（重複を除いたもの）。うち{bad}件に指摘（flags）が付いています。", "",
        "## 直しかた", "",
        "- `to_edit.jsonl` を直接編集してください（1行1件のJSON）。",
        "- `line` を書き直す。`facts` の数値がおかしい行は `facts` も直してよい。",
        "- 要らない行は `\"keep\": false` にする（行を消しても構いません）。",
        "- `flags` は目安なので、消しても直さなくても構いません。", "",
        "## 指摘の意味", "",
        "- 短い: 18字未満。ひとことすぎて学習には弱い",
        "- 文語: 「である」「なり」「せよ」など。話し言葉に直す",
        "- 句読点の乱れ / JSONの破片: 生成の失敗",
        "- 事実の数値が不自然: 「約4点損」のような将棋としてありえない値（桁上げは機械的に直し済み。残っているものだけ手で）",
        "- 気分の印なし(任意): その気分らしい語（ふむ／はは／……／うわ など）が無いという目安。直さなくてよい",
        "- 語尾がキャラでない: 「〜だ」「〜かね」など軍師の語尾が無い",
        "- 気分が出ていない: 大混乱なのに落ち着いている、など",
        "- 口調: 女性語・です/ます・人称のぶれ", "",
        "## 場面ごとの件数（目標 / 今ある数）", "",
        "| scene | 目標 | 今 |", "|---|---|---|",
        *[f"| {k} | {target[k]} | {have.get(k, 0)} |" for k in S],
        "", "直し終わったら `uv run python tools/check_edited.py data/finetune_gen_edit/to_edit.jsonl` で確認できます。",
    ]
    (OUT / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")
    print(f"{len(rows)}件 → data/finetune_gen_edit/to_edit.jsonl（指摘つき {bad}件）")


if __name__ == "__main__":
    main()
