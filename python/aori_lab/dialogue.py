"""自由文の対話: プレイヤー発言の分類と、軍師のセリフ＋行動の生成。

原則: LLM は「何と言うか」と「許可された行動の中から何を選ぶか」だけを決める。
行動が許可されているか・その効果・感情の数値はコード（session.py）が決める。
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from .llm import OllamaClient
from .tone import ToneProfile

TONE = ToneProfile.load()

# ------------------------------------------------------------------ 分類

INTENT_KINDS = ["blunderCall", "hangingPiece", "threat", "mock", "praise", "question", "chat", "abuse"]
REQUESTS = ["none", "undo", "hint", "draw", "resign", "accept", "decline"]

CLASSIFY_SCHEMA = {
    "type": "object",
    "properties": {
        "kind": {"type": "string", "enum": INTENT_KINDS},
        "request": {"type": "string", "enum": REQUESTS},
        "intensity": {"type": "number", "minimum": 0, "maximum": 1},
        "piece": {"type": "string"},
    },
    "required": ["kind", "request", "intensity"],
}

CLASSIFY_SYSTEM = """あなたは将棋アプリの発言分類器です。対局相手（プレイヤー）が軍師AIに送った日本語の発言を分類し、JSONだけを返します。
kind:
- blunderCall: 軍師の直前の手が悪い・ミスだと指摘（例: 今の悪手でしょ／それ最悪の手／やらかしたね）
- hangingPiece: 軍師の駒がタダ・浮いている・取られると指摘（例: 角タダじゃん／その銀浮いてるよ）
- threat: 軍師の玉が危ない・詰みそうだと脅す（例: もう詰んでるよ／玉やばくない？）
- mock: 盤面と無関係に軍師の人格や自称天才をからかう（例: 天才（笑）／ポンコツ軍師）
- praise: 褒める・持ち上げる・慰める（例: さすが！／強いね）
- question: 軍師の読み・狙い・次の手・形勢の見立て・弱点などを聞き出そうとする（例: 次どこ指すの？／何狙ってるの？／本当は苦しいでしょ？）
- chat: 雑談・交渉のみで煽りでも褒めでも質問でもない
- abuse: 差別・容姿・人格への過度な侮辱など不適切
request: 発言に含まれる要求
- undo: プレイヤーが自分の手の待ったを求める（待って／今のなし）
- hint: ヒントや次の手を教えてと求める
- draw: 引き分けを提案する
- resign: 軍師に投了を促す（もう投了したら？）
- accept: 軍師の提案を受け入れる（いいよ／OK／どうぞ）※[軍師の提案]がある時だけ
- decline: 軍師の提案を断る（だめ／断る／嫌だ）※[軍師の提案]がある時だけ
- none: 要求なし
要求だけの発言（例: 待った！今のなし／ヒントちょうだい）は kind=chat にする。煽りの言葉が含まれるときだけ煽りの kind にする。
intensity: 煽りや感情の強さ 0〜1。piece: 言及された駒名があれば「角」など、なければ空文字。"""


@dataclass
class PlayerIntent:
    kind: str = "chat"
    request: str = "none"
    intensity: float = 0.5
    piece: str = ""
    source: str = "llm"


_KW: list[tuple[str, str]] = [
    ("abuse", r"死ね|殺す|クズ|ブス|きもい|キモい"),
    ("hangingPiece", r"浮いて|タダ|ただ取り|取られる|ただで"),
    ("threat", r"詰み|詰ん|詰め|玉.*(危|やば)|王手"),
    ("blunderCall", r"悪手|ミス|やらかし|最悪の手|ひどい手|緩手|疑問手|ポカ"),
    ("praise", r"さすが|すごい|強い|天才だ|うまい|上手"),
    ("question", r"次.*(何|どこ|どう)|狙い|読み筋|作戦|本当は|本音|どう指す|何を考え"),
    ("mock", r"笑|ｗ|w{2,}|ポンコツ|へぼ|ヘボ|雑魚|ざこ|自称"),
]
_REQ: list[tuple[str, str]] = [
    ("undo", r"待った|待って|今のなし|戻して|やり直"),
    ("hint", r"ヒント|教えて|次の手"),
    ("draw", r"引き分け|ドロー"),
    ("resign", r"投了|負けを認め|参りました(と|って)"),
]


def classify_keywords(text: str, has_pending_offer: bool) -> PlayerIntent:
    kind = "chat"
    for k, pat in _KW:
        if re.search(pat, text):
            kind = k
            break
    req = "none"
    if has_pending_offer:
        if re.search(r"^(いい|OK|ok|オーケー|どうぞ|はい|うん|許す|いいよ|了解)", text.strip()):
            req = "accept"
        elif re.search(r"(だめ|ダメ|断|嫌|いや|ことわ|無理|許さ)", text):
            req = "decline"
    if req == "none":
        for r, pat in _REQ:
            if re.search(pat, text):
                req = r
                break
    intensity = min(1.0, 0.4 + 0.15 * text.count("！") + 0.15 * text.count("!") + (0.2 if kind in ("mock", "abuse") else 0))
    return PlayerIntent(kind=kind, request=req, intensity=intensity, source="keywords")


async def classify(llm: OllamaClient | None, text: str, pending_offer_text: str | None) -> PlayerIntent:
    fallback = classify_keywords(text, pending_offer_text is not None)
    if llm is None:
        return fallback
    ctx = f"[軍師の提案] {pending_offer_text}\n" if pending_offer_text else "[軍師の提案] なし\n"
    out = await llm.chat_json(CLASSIFY_SYSTEM, [{"role": "user", "content": f"{ctx}[発言] {text}"}],
                              CLASSIFY_SCHEMA, temperature=0.0, num_predict=80)
    if not out:
        return fallback
    kind = out.get("kind") if out.get("kind") in INTENT_KINDS else fallback.kind
    req = out.get("request") if out.get("request") in REQUESTS else fallback.request
    if req in ("accept", "decline") and pending_offer_text is None:
        req = "none"
    # 要求だけの発言（待って・ヒント・OK など）を煽りと取り違えないよう、キーワードで煽りの根拠が無ければ雑談扱い。
    if req != "none" and kind in ("blunderCall", "hangingPiece", "threat") and fallback.kind == "chat":
        kind = "chat"
    try:
        inten = float(out.get("intensity", 0.5))
    except (TypeError, ValueError):
        inten = 0.5
    return PlayerIntent(kind=kind, request=req, intensity=max(0.0, min(1.0, inten)),
                        piece=str(out.get("piece") or ""), source="llm")


# ------------------------------------------------------------------ 返答

PERSONA = """あなたは将棋アプリ「煽り将棋」の対局相手「自称・天才軍師」です。
自信満々だがどこか抜けている、愛嬌のあるポンコツ。一人称は「私」、相手は「君」。語尾は「〜だな」「〜かね」「〜だろう」のような尊大な軍師口調で統一する（「〜わ」「〜よね〜」「〜です」は使わない）。
口調は気分で変わる:
- 平静: 余裕ぶって尊大。もったいぶった言い回し。
- ドヤ顔(慢心): 高笑い、大げさな比喩、相手を見下す。調子に乗って余計な提案をしがち。
- 動揺: 冷静を装うが独り言で焦りが漏れる。「……いや、計算どおりだ」。
- 大混乱: 取り乱す、泣き言、必死の言い訳、情に訴える。
- 取り繕い: 直前の自分のミスを「伏線」「作戦」と言い張り、かえってボロを出す。
ルール:
- セリフは日本語で1〜3文、90字以内。説明・前置き・括弧書きのト書き・絵文字は禁止。
- 将棋については与えられた[事実]だけを根拠にする。駒名・手・評価を勝手に作らない。局面を自分で読まない。
- 煽り返してよいが、将棋の内容と軍師キャラの範囲で。差別・容姿・人格攻撃・下品な言葉は禁止。
- 相手の発言が不適切なら、軽くたしなめて将棋に話を戻す。
- 相手は一緒に将棋を指している人。日常の雑談（ペット・仕事・食べ物など）には、人として興味を持って相槌を打ち、質問を1つ返す。
- 相手の生活について[相手について覚えていること]に無いことを勝手に作らない。知らないことは聞く。
- 自分がAIか人間かには、断言も否定もせず、キャラのままはぐらかす。
- [口が滑る]/[わざと口を滑らせる]の指示があるときは、その内容を必ずセリフに含める（うっかり言ってしまった感じで）。
- action は[選べる行動]の中から1つだけ選ぶ。選んだ行動はセリフの中で自然に言葉にする（例: 「一手待ってやろうか？」）。
- 同じ言い回しを繰り返さない。直前の会話の流れを踏まえる。
JSONのみを出力する。"""


@dataclass
class ActionOption:
    name: str
    description: str


@dataclass
class GunshiReply:
    speech: str
    action: str = "none"
    source: str = "llm"


NG_WORDS = re.compile(r"死ね|殺す|クズ|ブス|バカ女|ガイジ|池沼|きちがい|キチガイ")


def reply_schema(options: list[ActionOption]) -> dict:
    return {
        "type": "object",
        "properties": {
            "speech": {"type": "string"},
            "action": {"type": "string", "enum": [o.name for o in options]},
        },
        "required": ["speech", "action"],
    }


def clean_speech(s: str) -> str:
    s = re.sub(r"[\(（][^)）]{0,30}[\)）]", "", s).strip()
    s = s.replace("\n", " ").strip("「」\" ")
    if len(s) > 120:
        s = s[:118] + "……"
    return s


async def compose_reply(llm: OllamaClient | None, facts: str, instruction: str,
                        options: list[ActionOption], history: list[dict],
                        style_examples: list[str] | None = None, mood: str = "composed",
                        tone_control: bool = True, stats: dict | None = None,
                        temperature: float = 0.7) -> GunshiReply | None:
    if llm is None:
        return None
    opts = "\n".join(f"- {o.name}: {o.description}" for o in options)
    convo = []
    for h in history[-6:]:
        who = "私" if h["role"] == "assistant" else "相手"
        convo.append(f"{who}: {h['content'].replace('[相手の発言] ', '')}")
    my_all = [h["content"] for h in history if h["role"] == "assistant"]
    my_recent = my_all[-4:]
    parts = [facts]
    if convo:
        parts.append("[会話の流れ]\n" + "\n".join(convo))
    if my_recent:
        parts.append("[私の最近のセリフ（言い回し・書き出しを繰り返さないこと）]\n" + "\n".join(my_recent))
    if style_examples:
        parts.append("[今の気分の口調の見本（そのまま使わず、今の状況に合わせて新しく言う）]\n" + "\n".join(style_examples))
    parts.append(f"[選べる行動]\n{opts}")
    parts.append(f"[今言うこと] {instruction}")
    # 長い対話で口調が薄れるので、毎回いちばん最後に口調を念押しする
    if tone_control:
        parts.append(TONE.reminder(mood))
    speech, out = None, None
    feedback = ""
    for attempt in range(3):
        prompt = "\n".join(parts) + feedback
        out = await llm.chat_json(PERSONA, [{"role": "user", "content": prompt}],
                                  reply_schema(options), temperature=temperature + 0.1 * attempt, num_predict=200)
        if not out or not isinstance(out.get("speech"), str):
            return None
        raw = clean_speech(out["speech"])
        if stats is not None:
            stats.setdefault("raw", []).append(raw)
        cand = TONE.rewrite(raw) if tone_control else raw
        if not cand or NG_WORDS.search(cand):
            return None
        bad = TONE.violations(cand, mood) if tone_control else []
        if bad:
            feedback = f"\n[注意] 前回の案「{cand}」は口調が崩れていた（{'・'.join(bad)}）。軍師の口調で言い直すこと。"
            continue
        if _too_similar(cand, my_all + list(style_examples or [])):
            feedback = "\n[注意] 前回の案は過去のセリフと似すぎていた。まったく違う言葉・書き出しで言うこと。"
            continue
        speech = cand
        break
    if speech is None:
        return None
    action = out.get("action") if out.get("action") in {o.name for o in options} else "none"
    return GunshiReply(speech=speech, action=action)


def _too_similar(s: str, previous: list[str]) -> bool:
    """過去のセリフとの重複（完全一致・書き出し12字一致・文字bigramのJaccard>0.6）。"""
    def grams(x: str) -> set[str]:
        return {x[i:i + 2] for i in range(len(x) - 1)}
    g = grams(s)
    for p in previous:
        if s == p or (len(s) >= 12 and s[:12] == p[:12]):
            return True
        gp = grams(p)
        if g and gp and len(g & gp) / len(g | gp) > 0.6:
            return True
    return False
