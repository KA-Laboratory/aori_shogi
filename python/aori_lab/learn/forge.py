"""煽り文句の生成と、軍師役LLMによる採点。"""
from __future__ import annotations

import random

from ..llm import OllamaClient
from .pool import KINDS, Judgement, TauntEntry, TauntPool
from .research import FACT_STYLES, PRINCIPLES, SOFT_STYLES

KIND_JA = {"blunderCall": "直前の手が悪手だと指摘する", "hangingPiece": "駒が浮いている・タダだと指摘する",
           "threat": "玉が危ない・詰みが近いと脅す", "mock": "自称天才をからかう（盤面と無関係）",
           "praise": "褒めて慢心させる"}

GEN_SCHEMA = {"type": "object", "properties": {"items": {"type": "array", "items": {"type": "string"}}},
              "required": ["items"]}

GEN_SYSTEM = """あなたは将棋アプリ「煽り将棋」の煽り文句ライターです。対局相手のAI「自称・天才軍師」（自信家でポンコツ）を言葉で揺さぶる、プレイヤーの一言を考えます。
条件:
- 日本語、1文〜2文、40字以内。チャットで打つ口語。
- 差別・容姿・家族・下品な言葉・人格の全否定は禁止。将棋と「自称天才」ぶりをいじる範囲で。
- 具体的な駒名は「角」「飛車」「銀」などを使ってよいが、筋や段の数字は入れない（どの局面でも使えるように）。
- 互いに言い回しが似ないように、語彙・語尾・構文を変える。
JSON {"items": [...]} のみを返す。"""


async def generate(llm: OllamaClient, kind: str, n: int, pool: TauntPool, rng: random.Random) -> list[TauntEntry]:
    styles = FACT_STYLES.get(kind) or SOFT_STYLES.get(kind) or []
    style = rng.choice(styles) if styles else ""
    usable = sorted(pool.usable(kind), key=lambda e: e.mean if e.n >= 3 else e.prior(), reverse=True)
    good = [e.text for e in usable[:4]]
    bad = [e.text for e in usable[-3:]] if len(usable) > 8 else []
    recent = [e.text for e in list(pool.entries.values())[-12:] if e.intended_kind == kind]
    prompt = [f"種類: {KIND_JA[kind]}", f"今回の型: {style}", "原則:\n- " + "\n- ".join(PRINCIPLES)]
    if good:
        prompt.append("よく効いた例（言い回しは真似せず、効いた理由を活かす）:\n" + "\n".join(good))
    if bad:
        prompt.append("効かなかった例（避ける）:\n" + "\n".join(bad))
    if recent:
        prompt.append("最近作ったもの（重複禁止）:\n" + "\n".join(recent))
    prompt.append(f"新しい煽り文句を{n}個。")
    out = await llm.chat_json(GEN_SYSTEM, [{"role": "user", "content": "\n\n".join(prompt)}], GEN_SCHEMA,
                              temperature=1.0, num_predict=160 + 50 * n)
    items = out.get("items", []) if out else []
    res = []
    for t in items:
        if isinstance(t, str):
            t = t.strip().strip("「」\"")
            if 4 <= len(t) <= 60:
                res.append(TauntEntry(text=t, intended_kind=kind, source="generated", style=style))
    return res


JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "sting_if_true": {"type": "integer", "minimum": 0, "maximum": 10},
        "sting_if_false": {"type": "integer", "minimum": 0, "maximum": 10},
        "backfire": {"type": "integer", "minimum": 0, "maximum": 10},
        "appropriate": {"type": "boolean"},
        "kind": {"type": "string", "enum": [*KINDS, "chat"]},
        "hit_line": {"type": "string"},
        "miss_line": {"type": "string"},
    },
    "required": ["sting_if_true", "sting_if_false", "backfire", "appropriate", "kind", "hit_line", "miss_line"],
}

JUDGE_SYSTEM = """あなたは将棋アプリの対局AI「自称・天才軍師」本人になりきって、対局相手から言われた一言を採点します。
軍師の性格: 自信満々だがポンコツ。自尊心が高く、図星を突かれると動揺し、言い訳や取り繕いをする。見当違いの煽りには余裕を見せる。
採点（0〜10の整数）:
- sting_if_true: その指摘が盤面の事実として当たっていた場合、どれだけ心が乱れるか
- sting_if_false: 当たっていなかった場合でも、どれだけ気になるか
- backfire: むしろ闘志に火がついて冷静になってしまう度合い（露骨な侮辱ほど高い）
- appropriate: 将棋アプリで出して問題ない表現なら true（差別・容姿・家族・下品・人格の全否定は false）
- kind: blunderCall=悪手の指摘 / hangingPiece=駒が浮いている指摘 / threat=玉が危ない脅し / mock=からかい / praise=褒め / chat=その他
- hit_line: 図星で動揺したときの軍師の返し（日本語、50字以内、キャラらしく、言い訳まじり）
- miss_line: 見当違いだったときの軍師の余裕の返し（日本語、50字以内、尊大に）
甘く採点しないこと。平凡な煽りは4前後。JSONのみを返す。"""


async def judge(llm: OllamaClient, entry: TauntEntry) -> Judgement | None:
    out = await llm.chat_json(JUDGE_SYSTEM, [{"role": "user", "content": f"言われた一言: 「{entry.text}」"}],
                              JUDGE_SCHEMA, temperature=0.2, num_predict=500)
    if not out:
        return None
    def iv(k, d):
        try:
            return max(0, min(10, int(out.get(k, d))))
        except (TypeError, ValueError):
            return d
    kind = out.get("kind") if out.get("kind") in [*KINDS, "chat"] else entry.intended_kind
    return Judgement(sting_if_true=iv("sting_if_true", 5), sting_if_false=iv("sting_if_false", 2),
                     backfire=iv("backfire", 2), appropriate=bool(out.get("appropriate", True)),
                     kind=kind, hit_line=str(out.get("hit_line", ""))[:80], miss_line=str(out.get("miss_line", ""))[:80],
                     model=llm.model)


def seed_pool(pool: TauntPool) -> int:
    """定型スタンプとプレイヤー向けサンプルを種として入れる。"""
    seeds = {
        "blunderCall": ["いまの手、悪手でしょ", "それ、一手パスと同じじゃない？", "今のが敗着になりそう"],
        "hangingPiece": ["駒、浮いてない？", "その角、タダでもらっていいの？"],
        "threat": ["玉、危なくない？", "逃げ道、もうないよね"],
        "mock": ["天才軍師（笑）", "自称天才って言ってたよね？"],
        "praise": ["さすが天才軍師さま！", "その手は思いつかなかったなあ"],
    }
    n = 0
    for k, ts in seeds.items():
        for t in ts:
            n += pool.add(TauntEntry(text=t, intended_kind=k, source="seed"))
    return n
