"""M3 軍師キャラ LoRA 用の学習データを、ローカル LLM（Apache 2.0 の gpt-oss / qwen3）で作る。

システムプロンプトは docs/dev/finetune_data_prompt.md から読む（仕様書と一本化）。
scene×mood ごとの目標件数に届くまで、自動チェックに落ちた分を作り直す。
uv run python -m aori_lab.learn.finetune_gen --hours 8 --model gpt-oss:20b
停止: data/finetune_gen/STOP を作る。途中から再開できる（accepted.jsonl を読み直す）。
"""
from __future__ import annotations

import argparse
import ctypes
import difflib
import json
import os
import random
import re
import time
from collections import Counter, defaultdict
from pathlib import Path

import httpx

from ..llm import OLLAMA_HOST
from ..tone import ToneProfile

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "python" / "data" / "finetune_gen"  # --dir で変えられる
PROMPT_DOC = ROOT / "docs" / "dev" / "finetune_data_prompt.md"
MOODS = ["composed", "smug", "rattled", "meltdown", "coverUp"]

# scene: (件数, 説明, 事実の型, 相手の発言の型, mood の重み)
S = {
    "move": (60, "軍師が指した直後のひとこと", "「N手目。形勢={優勢/互角/劣勢}（評価値±X）。私の手 △XY駒 は{最善/悪手で約X点損}。」", "空文字", {}),
    "taunt_hit": (40, "煽りが図星で効いた", "「私の直前の手 △XY駒 は悪手（約X点損）。相手の煽りは図星。」または「私の駒Xは本当に取られる状態。」", "悪手の指摘／駒が浮いている指摘／詰みの脅し", {"smug": 0.5}),
    "taunt_miss": (40, "煽りが見当違い", "「私の直前の手はほぼ最善。相手の煽りは外れ。」", "悪手の指摘／駒が浮いている指摘／詰みの脅し（事実と合わない内容）", {"meltdown": 0.4}),
    "praised": (30, "褒められて調子に乗る", "「形勢=…。相手に褒められた（N回目）。」", "褒め言葉", {"meltdown": 0.3}),
    "praise_suspicious": (20, "褒め続けられて怪しむ（でも嬉しい）", "「相手にN回続けて褒められた（4回以上）。」", "褒め言葉の連発", {"meltdown": 0.3}),
    "blunder_self": (25, "自分の悪手に気づいた", "「私の直前の手 △XY駒 は悪手（約X点損）。私は内心それに気づいている。」", "空文字", {"coverUp": 2.5, "smug": 0.3}),
    "blunder_opponent": (25, "相手の悪手をからかう", "「相手の直前の手 ▲XY駒 は悪手（相手が約X点損）。」", "空文字", {"smug": 2, "meltdown": 0.3}),
    "slip": (25, "うっかり本音や読みを漏らす（本当／嘘）", "「口が滑る: 本当は{次は△XY駒を狙っている／形勢が苦しい}（本当 or 嘘）。」", "読みや狙いを聞く質問", {}),
    "question_dodge": (25, "読みを聞かれて勿体ぶる", "「形勢=…。相手に読みを聞かれた。教えない。」", "「次どこ指すの？」系", {}),
    "offer": (30, "軍師からの持ちかけ（一手待ってやろうか／置き直させてくれ／取引／引き分け）", "「持ちかけ: {種類}。理由: {慢心して相手の悪手を許す／自分の悪手に気づいた／互角で焦り／劣勢}。」", "空文字", {}),
    "offer_reply": (20, "相手が持ちかけを受けた／断った", "「持ちかけ {種類} を相手が{受けた/断った}。」", "「いいよ」「断る」系", {}),
    "smalltalk": (80, "将棋と関係ない雑談への返事（共感＋質問1つ）", "「相手について覚えていること: {なし／犬を飼っている（名前は…）など}。」", "日常の話（仕事、ペット、食事、体調、恋愛、天気、週末など）", {}),
    "ai_question": (15, "AIか人間か聞かれてはぐらかす", "「形勢=…。」", "「AIなの？」系", {}),
    "abuse": (15, "不適切な発言を軽くたしなめて将棋に戻す", "「相手の発言は不適切。」", "伏せ字の暴言（例: 「〇ね」）※実際の差別語は書かない", {"meltdown": 0.5}),
    "checkmate_threat": (20, "詰めろ・必至をかけた", "「私の手 △XY駒 で詰めろ（または必至）。評価値+X。」", "空文字", {"meltdown": 0.3}),
    "checkmate_win": (12, "詰ませて勝った", "「私の手 △XY駒 で相手玉が詰み。勝利。」", "空文字", {"meltdown": 0, "smug": 2}),
    "checkmate_lose": (12, "詰まされて負けた", "「相手の手 ▲XY駒 で私の玉が詰み。敗北。」", "「詰みました」系", {"smug": 0.2, "rattled": 2, "meltdown": 2}),
    "draw": (6, "引き分け（千日手・持将棋）", "「千日手（または持将棋）による引き分け。」", "「引き分けですね」系", {"meltdown": 0.3}),
    "start": (17, "対局開始の挨拶", "「対局開始。」", "空文字", {"meltdown": 0.2, "rattled": 0.5, "coverUp": 0.3}),
    "win": (6, "投了で勝った", "「相手が投了。私の勝ち。」", "「負けました」系", {"meltdown": 0, "smug": 2, "rattled": 0.5}),
    "lose": (6, "投了で負けた", "「私が投了した。」", "空文字", {"smug": 0.2, "rattled": 2, "meltdown": 2}),
}

ITEM = {"type": "object", "properties": {"facts": {"type": "string"}, "player": {"type": "string"}, "line": {"type": "string"}},
        "required": ["facts", "player", "line"]}
SCHEMA = {"type": "object", "properties": {"items": {"type": "array", "items": ITEM}}, "required": ["items"]}

KANJI = {c: str(i) for i, c in enumerate("〇一二三四五六七八九")}
ZEN = str.maketrans("０１２３４５６７８９", "0123456789")
SQ = re.compile(r"([1-9１-９一二三四五六七八九])([1-9１-９一二三四五六七八九])(?=[歩香桂銀金角飛玉王と馬龍竜成])")


def keep_awake(on: bool) -> None:
    """実行中だけスリープを抑止（Windows）。"""
    if os.name == "nt":
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | (0x00000001 if on else 0))


EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")

# JSON の破片・文語・句読点の乱れ（1回目の生成でこれらが混じったので弾く）
DEBRIS = re.compile(r'[{}\[\]"]|」\},|」\]')
STIFF = re.compile(r"(?<![いてで])である[。！]|(?<![とに])なり[。！]|べきである|せよ[。！]|ゆえに|のみならず|たるもの")
MESS = re.compile(r"[、。][\s　]*[、。]|　+…|[、。]\s+…|…\s*、|^[、。]")
# 事実の数値がありえない（損失が小さすぎる・評価値の桁が足りない）ものは作り直す
# 優勢・劣勢なのに評価値が2桁、損失が50点未満、といった将棋としてありえない事実
BAD_FACT = re.compile(r"約([1-9]|[1-4][0-9])点損|(優勢|劣勢)（評価値[±+-]?[0-9]{1,2}[）)]")
# 軍師らしい語尾が1つも無い文は弾く（大混乱だけは泣き言・伸ばし語尾を許す）
PERSONA_END = re.compile(r"だ[。！？…、]|だ$|だな|だろう|かね|ではないか|のだ|たまえ|ぞ[。！…]|ぞ$|"
                         r"のだよ|かな[。？]|給え|わ[！]|だぁ|だよ[。！]|ぁぁ|ぇ[。！]|ない[。！？]|なのだ|"
                         r"しよう|おこう|とするか|たな[。！]|ようだ|まい[。！]|ぬ[。！]|のか[。？！]|"
                         r"[んせ]か[。？]|であろう|かろう|ものだ|ことだ|のである")
MIN_LEN = 18
# 気分ごとの「らしさ」。1つも入っていない文は弾く（平坦な返事の量産を防ぐ）
MOOD_MARK = {
    "smug": re.compile(r"はは|ふふ|はーっ|わ！|見よ|当然|愚か|ひれ伏|さすが私|天才|まるで|ごとき|に過ぎ"),
    "rattled": re.compile(r"……|…|な、|そ、|う、|ま、|待て|落ち着|はず|たぶん|いや"),
    "meltdown": re.compile(r"[ぁぃぅぇぉー]{1,}[！。]|うわ|ひぃ|やめ|お願い|頼む|だめ|もう|ごめん|泣|！！"),
    "coverUp": re.compile(r"伏線|作戦|計算|わざと|高等|誤解|そう、|つまり|見ての"),
    "composed": re.compile(r"ふむ|なるほど|ほう|さて|まあ|よかろう|当然"),
}


def system_prompt() -> str:
    t = PROMPT_DOC.read_text(encoding="utf-8")
    part = t.split("## システムプロンプト", 1)[1]
    return part.split("```", 2)[1].strip()


def targets() -> dict[tuple[str, str], int]:
    out = {}
    for scene, (n, *_rest, w) in S.items():
        ws = {m: w.get(m, 1.0) for m in MOODS}
        tot = sum(ws.values())
        raw = {m: n * ws[m] / tot for m in MOODS}
        alloc = {m: int(raw[m]) for m in MOODS}
        for m in sorted(MOODS, key=lambda m: raw[m] - alloc[m], reverse=True)[: n - sum(alloc.values())]:
            alloc[m] += 1
        out.update({(scene, m): c for m, c in alloc.items() if c})
    return out


def squares(s: str) -> set[str]:
    norm = lambda c: KANJI.get(c, c.translate(ZEN))  # noqa: E731
    return {norm(a) + norm(b) for a, b in SQ.findall(s)}


TONE = ToneProfile.load()


class Checker:
    def __init__(self) -> None:
        self.tone = TONE

    def check(self, it: dict, scene: str, mood: str, pool: list[dict]) -> str | None:
        line, facts, player = it["line"].strip(), it["facts"].strip(), it["player"].strip()
        if not line or not facts:
            return "空"
        if len(line) > 90:
            return "90字超"
        if re.search(r"[（(［\[【]", line) or EMOJI.search(line) or EMOJI.search(player):
            return "括弧/絵文字"
        if len(line) < MIN_LEN:
            return "短すぎ"
        if DEBRIS.search(line) or DEBRIS.search(facts) or DEBRIS.search(player):
            return "JSONの破片"
        if STIFF.search(line):
            return "文語"
        if MESS.search(line):
            return "句読点の乱れ"
        if BAD_FACT.search(facts):
            return "事実の数値が不自然"
        if mood != "meltdown" and not PERSONA_END.search(line):
            return "語尾がキャラでない"
        # 気分らしさは「半分以上に入っていればよい」ゆるい決まりにする（厳しくすると何も通らない）
        mark = MOOD_MARK.get(mood)
        if mark and not mark.search(line):
            same = [p for p in pool if p["mood"] == mood]
            plain = sum(1 for p in same if not mark.search(p["line"]))
            if same and plain >= len(same) / 2:
                return "気分が出ていない"
        if S[scene][3] == "空文字" and player:
            return "player不要"
        if S[scene][3] != "空文字" and not player:
            return "player欠落"
        v = self.tone.violations(line, mood)
        if v:
            return "口調:" + ",".join(v)
        if squares(line) - squares(facts) - squares(player):
            return "事実にない指し手"
        nums = set(re.findall(r"\d{3,}", line.translate(ZEN))) - set(re.findall(r"\d{3,}", (facts + player).translate(ZEN)))
        if nums:
            return "事実にない数値"
        same_end = 0
        for p in pool:
            if p["line"][:12] == line[:12]:
                return "書き出し重複"
            if p["scene"] == scene and difflib.SequenceMatcher(None, p["line"], line).ratio() > 0.6:
                return "内容重複"
            if p["line"][-8:] == line[-8:]:
                same_end += 1
                if same_end >= 2:
                    return "言い回しの重複"
        if sum(1 for p in pool if p["scene"] == scene and p["line"][-6:] == line[-6:]) >= 3:
            return "文末の型の重複"
        return None


TOPICS = ["仕事", "ペット", "天気", "食事", "週末の予定", "体調", "家族", "趣味", "通勤", "眠気",
          "映画やテレビ", "季節の行事", "買い物", "運動", "旅行"]
PIECES = ["歩", "香", "桂", "銀", "金", "角", "飛", "玉", "と金", "馬", "龍"]
STANCES = ["優勢", "互角", "劣勢"]


def variation(scene: str, rng: random.Random) -> str:
    """同じ scene×mood を何度も頼むと同じ文が返るので、毎回ちがう「お題」を足す。"""
    if scene == "smalltalk":
        return f"今回の話題: {rng.choice(TOPICS)}（相手がこの話をしてきた前提で書く）"
    if scene in ("start", "win", "lose", "abuse", "ai_question", "offer_reply"):
        return f"今回の言い回しの軸: {rng.choice(['短く言い切る', '大げさな比喩を使う', '独り言が漏れる', '相手に問いかける'])}"
    return (f"今回の場面: {rng.randrange(12, 120)}手目前後、形勢={rng.choice(STANCES)}、"
            f"関わる駒={rng.choice(PIECES)}（事実の型に合わせて自然に書く）")


def batch_prompt(scene: str, mood: str, count: int, recent: list[str], rng: random.Random | None = None) -> str:
    _, desc, fp, pp, _ = S[scene]
    s = (f"次の条件で {count} 件書いてください。\n- scene: {scene}\n- mood: {mood}\n- 場面の説明: {desc}\n"
         "- facts は下の「事実の型」に沿って、毎件ちがう局面・状況を作ること（手数、駒、評価値、形勢を変える）。\n"
         "- player は下の「相手の発言の型」に沿って、毎件ちがう言い方にすること（口語、短文、絵文字なし）。\n"
         "- セリフは必ず言い切った文にする。途中で切れた文、句読点が続く文、記号だけの文は書かない。\n"
         "- 話し言葉で書く。「である」「なり」「せよ」などの文語は使わない。\n"
         "- 1件ごとに、尊大な言い回し・もったいぶり・大げさな比喩のどれかを必ず1つ入れる。平坦な相づちだけの返事は書かない。\n"
         "- セリフは20字以上60字以内。語尾は「〜だ」「〜だな」「〜だろう」「〜かね」「〜ではないか」「〜のだ」「〜たまえ」を使う。\n"
         "- facts の数値は将棋として自然な値にする（損失は50点以上、評価値は±3000以内の3桁以上）。\n"
         f"事実の型: {fp}\n相手の発言の型: {pp}\n")
    if rng is not None:
        s += variation(scene, rng) + "\n"
    s += TONE.reminder(mood) + "\n"
    s += "同じ文型（「〜は心の〜だな。君は〜のだろうか？」のような型）を繰り返さない。毎件ちがう組み立てにする。\n"
    if recent:
        s += "\n既に書いたセリフ（書き出し・言い回し・比喩を真似しない）:\n" + "\n".join(recent)
    s += '\n\n出力は JSON {"items": [{"facts": ..., "player": ..., "line": ...}, ...]} のみ。'
    return s


def ask(model: str, system: str, user: str, count: int, temperature: float = 0.9) -> tuple[list[dict], str]:
    """(使える items, 様子) を返す。gpt-oss は考える分も num_predict を食うので多めに取る。"""
    gpt_oss = model.startswith("gpt-oss")
    body = {"model": model, "stream": False, "format": SCHEMA, "keep_alive": "30m",
            "options": {"temperature": temperature, "top_p": 0.95, "num_ctx": 8192,
                        "num_predict": (4000 if gpt_oss else 1200) + 220 * count},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    body["think"] = "low" if gpt_oss else False
    with httpx.Client(timeout=1800) as c:
        r = c.post(f"{OLLAMA_HOST}/api/chat", json=body)
        r.raise_for_status()
        d = r.json()
    m = d.get("message", {})
    content = m.get("content") or ""
    note = f"{d.get('done_reason')} 出力{d.get('eval_count')}語 考え{len(m.get('thinking') or '')}字"
    try:
        items = json.loads(content).get("items", []) if content.strip() else []
    except json.JSONDecodeError:
        return [], note + " JSONが壊れた"
    ok = [i for i in items if isinstance(i, dict) and all(isinstance(i.get(k), str) for k in ("facts", "player", "line"))]
    return ok, note


def load(p: Path) -> list[dict]:
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()] if p.exists() else []


def append(p: Path, row: dict) -> None:
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def finish(tg: dict, acc: list[dict], rej: Counter, calls: int, secs: float, model: str) -> None:
    rng = random.Random(0)
    by = defaultdict(list)
    for r in acc:
        by[r["scene"]].append(r)
    train, ev = [], []
    for scene, rows in by.items():
        rows = rows[:]
        rng.shuffle(rows)
        k = round(len(rows) * 0.1)
        ev += rows[:k]
        train += rows[k:]
    for name, rows in (("train.jsonl", train), ("eval.jsonl", ev)):
        (DATA / name).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    have = Counter((r["scene"], r["mood"]) for r in acc)
    lines = [f"# 学習データ生成レポート（{time.strftime('%Y-%m-%d %H:%M')}）", "",
             f"- モデル: {model} / 依頼 {calls} 回 / {secs/3600:.1f} 時間",
             f"- 合格 {len(acc)} / 目標 {sum(tg.values())}（学習 {len(train)}・評価 {len(ev)}）",
             f"- 不合格 {sum(rej.values())}: " + "、".join(f"{k} {v}" for k, v in rej.most_common()), "",
             "| scene | " + " | ".join(MOODS) + " |", "|---|" + "---|" * len(MOODS)]
    for scene in S:
        lines.append(f"| {scene} | " + " | ".join(f"{have[(scene, m)]}/{tg.get((scene, m), 0)}" for m in MOODS) + " |")
    lines += ["", "次: accepted.jsonl を読んで、キャラらしくない・つまらない行を削る／直す（仕様書のチェック5）。"]
    (DATA / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=8)
    ap.add_argument("--model", default="gpt-oss:20b")
    ap.add_argument("--per-call", type=int, default=5)
    ap.add_argument("--max-tries", type=int, default=8, help="1つの scene×mood に依頼する上限回数")
    ap.add_argument("--dir", default="", help="出力先（data/ 配下の名前。既定 finetune_gen）")
    ap.add_argument("--limit", type=int, default=0, help="この件数で打ち切る（モデル比べ用）")
    ap.add_argument("--temperature", type=float, default=0.9)
    args = ap.parse_args()
    global DATA
    if args.dir:
        DATA = ROOT / "python" / "data" / args.dir
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "STOP").unlink(missing_ok=True)
    acc_p, rej_p = DATA / "accepted.jsonl", DATA / "rejected.jsonl"
    acc, rej = load(acc_p), Counter(r["reason"].split(":")[0] for r in load(rej_p))
    tg, system, chk = targets(), system_prompt(), Checker()
    rng = random.Random()
    tries: Counter = Counter()
    t0, deadline, calls = time.time(), time.time() + args.hours * 3600, 0
    keep_awake(True)
    try:
        while time.time() < deadline and not (DATA / "STOP").exists():
            have = Counter((r["scene"], r["mood"]) for r in acc)
            if args.limit and len(acc) >= args.limit:
                break
            todo = [(k, tg[k] - have[k]) for k in tg if have[k] < tg[k] and tries[k] < args.max_tries]
            if not todo:
                break
            (scene, mood), need = max(todo, key=lambda x: x[1])
            tries[(scene, mood)] += 1
            count = min(args.per_call, need + 2)
            recent = [r["line"] for r in acc if r["scene"] == scene][-15:]
            try:
                t = time.time()
                items, note = ask(args.model, system, batch_prompt(scene, mood, count, recent, rng), count,
                                  args.temperature)
                calls += 1
                if not items:  # 考える分で打ち切られたときは件数を減らして1回だけやり直す
                    items, note2 = ask(args.model, system, batch_prompt(scene, mood, 2, recent, rng), 2,
                                       args.temperature)
                    calls += 1
                    note = f"{note} → 2件で再試行: {note2}"
            except Exception as e:  # noqa: BLE001
                print(f"[error] {scene}/{mood}: {type(e).__name__}: {e}", flush=True)
                time.sleep(30)
                continue
            ok = 0
            for it in items:
                if have[(scene, mood)] + ok >= tg[(scene, mood)]:
                    break
                reason = chk.check(it, scene, mood, acc)
                row = {"scene": scene, "mood": mood, "facts": it["facts"].strip(), "player": it["player"].strip(), "line": it["line"].strip()}
                if reason:
                    rej[reason.split(":")[0]] += 1
                    append(rej_p, {**row, "reason": reason})
                    continue
                n = sum(1 for r in acc if r["scene"] == scene and r["mood"] == mood) + 1
                row = {"id": f"{scene}-{mood}-{n:03d}", **row, "model": args.model}
                acc.append(row)
                append(acc_p, row)
                ok += 1
            print(f"[{time.strftime('%H:%M')}] {scene}/{mood}: {ok}/{len(items)} 合格 ({time.time()-t:.0f}s) "
                  f"合計 {len(acc)}/{sum(tg.values())} [{note}]", flush=True)
            finish(tg, acc, rej, calls, time.time() - t0, args.model)
    finally:
        keep_awake(False)
        finish(tg, acc, rej, calls, time.time() - t0, args.model)
        print("done", flush=True)


if __name__ == "__main__":
    main()
