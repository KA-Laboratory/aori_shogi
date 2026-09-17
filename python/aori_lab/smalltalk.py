"""たわいのない雑談と、相手について覚えておく記憶。

- 将棋と関係ない話（犬の散歩、仕事、晩ごはん…）には、人として共感し、まだ知らないことを1つ聞き返す。
- 相手が話した事実（犬種・名前など）を抜き出して端末内に保存し、次の対局以降の会話で使う。
- LLM は「何を覚えるか」を提案するだけ。保存してよいか（相手が本当に言ったか・機微情報でないか）はコードが決める。
- 保存形式は Dart 版（lib/core/dialogue/player_memory.dart 予定）と共通の JSON。
"""
from __future__ import annotations

import json
import re
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .llm import OllamaClient

MEMORY_PATH = Path(__file__).resolve().parents[1] / "data" / "memory" / "player_memory.json"
TOPICS = ["pet", "family", "work", "school", "hobby", "food", "place", "event", "other"]

# 覚えてはいけない話題（住所・連絡先・お金・思想信条・性的な話）。含む事実は保存しない。
# 健康・恋愛の話は覚えてよい（2026-09-17 オーナー判断）。端末内のみ保存し、一覧から消せる。
SENSITIVE = re.compile(
    r"住所|番地|丁目|マンション名|電話|メール|@|パスワード|暗証|口座|カード番号|"
    r"年収|給料|借金|ローン|貯金|資産|"
    r"宗教|信仰|政党|支持政党|選挙で|性的|"
    r"\d{3,}-\d{2,}|\d{7,}"
)
# 将棋の話かどうか（雑談扱いにしない）
SHOGI_WORDS = re.compile(r"将棋|指す|指し|駒|王手|詰み|詰ん|詰め|悪手|好手|定跡|戦法|囲い|飛車|桂馬|香車|投了|待った|軍師|手番|盤|対局|先手|後手|タダ|ただ取り|浮いて|浮き駒|取られる|成り|成る")
# 1文字の駒名は「散歩」「金曜」「角度」「玉ねぎ」を除くため、前が漢字でなく後ろが助詞などの時だけ
PIECE1 = re.compile(r"(?<![\u4E00-\u9FFF々])[角金銀桂香歩玉飛馬龍竜](?=[がをにはでものとだじ、。!！?？]|$)")
AI_QUESTION = re.compile(r"(AI|ＡＩ|ai|エーアイ|人工知能|ロボット|機械|プログラム|bot|ボット|中の人|人間).{0,8}(\?|？|なの|でしょ|だろ|ですか|か$)")


@dataclass
class MemoryFact:
    key: str            # 何についてか（例: 犬の名前）
    value: str          # 値（例: ポチ）
    topic: str = "other"
    text: str = ""      # 自然文（例: 犬を飼っている。名前はポチ）
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:10])
    first_seen: str = field(default_factory=lambda: time.strftime("%Y-%m-%d %H:%M"))
    last_seen: str = field(default_factory=lambda: time.strftime("%Y-%m-%d %H:%M"))
    mentions: int = 1
    quote: str = ""     # 根拠になった相手の発言


class MemoryStore:
    def __init__(self, path: Path = MEMORY_PATH) -> None:
        self.path = path
        self.facts: list[MemoryFact] = []
        self.load()

    def load(self) -> None:
        if self.path.exists():
            d = json.loads(self.path.read_text(encoding="utf-8"))
            self.facts = [MemoryFact(**f) for f in d.get("facts", [])]

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"version": 1, "facts": [asdict(f) for f in self.facts]},
                                        ensure_ascii=False, indent=1), encoding="utf-8")

    def delete(self, fact_id: str) -> bool:
        n = len(self.facts)
        self.facts = [f for f in self.facts if f.id != fact_id]
        if len(self.facts) != n:
            self.save()
            return True
        return False

    def clear(self) -> None:
        self.facts = []
        self.save()

    def upsert(self, fact: MemoryFact) -> MemoryFact:
        for f in self.facts:
            if f.key == fact.key:
                f.value, f.text, f.topic = fact.value, fact.text or f.text, fact.topic
                f.last_seen, f.mentions, f.quote = fact.last_seen, f.mentions + 1, fact.quote or f.quote
                self.save()
                return f
        self.facts.append(fact)
        self.save()
        return fact

    def relevant(self, text: str, limit: int = 6) -> list[MemoryFact]:
        """今の発言に関係しそうな記憶を先に、残りは最近のものから。"""
        def score(f: MemoryFact) -> tuple:
            hit = any(w and w in text for w in (f.key, f.value, *_topic_words(f.topic)))
            return (hit, f.last_seen)
        return sorted(self.facts, key=score, reverse=True)[:limit]

    def prompt_block(self, text: str) -> str:
        facts = self.relevant(text)
        if not facts:
            return "[相手について覚えていること] まだ何も知らない。"
        return "[相手について覚えていること（本人から聞いた事実だけ）]\n" + "\n".join(
            f"- {f.text or f'{f.key}: {f.value}'}（{f.first_seen[:10]}に聞いた）" for f in facts)


def _topic_words(topic: str) -> tuple[str, ...]:
    return {"pet": ("犬", "猫", "散歩", "ペット"), "family": ("家族", "子ども", "妻", "夫", "母", "父"),
            "work": ("仕事", "会社", "残業"), "school": ("学校", "授業", "テスト"), "hobby": ("趣味",),
            "food": ("ごはん", "ご飯", "食べ", "飲み"), "place": ("旅行", "行った"), "event": ("今日", "週末")}.get(topic, ())


def is_smalltalk(text: str) -> bool:
    return not SHOGI_WORDS.search(text) and not PIECE1.search(text)


def asks_if_ai(text: str) -> bool:
    return bool(AI_QUESTION.search(text))


# ------------------------------------------------------------------ 抽出

EXTRACT_SCHEMA = {
    "type": "object",
    "properties": {
        "facts": {"type": "array", "items": {"type": "object", "properties": {
            "topic": {"type": "string", "enum": TOPICS},
            "key": {"type": "string"}, "value": {"type": "string"}, "text": {"type": "string"},
            "quote": {"type": "string"}}, "required": ["topic", "key", "value", "text", "quote"]}},
        "unknown": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["facts", "unknown"],
}
EXTRACT_SYSTEM = """あなたは会話メモ係です。将棋の対局相手（プレイヤー）が雑談で話した、本人の生活についての事実を抜き出します。
- 本人がはっきり言ったことだけ。推測・一般論・軍師の発言は入れない。
- key は「犬の種類」「犬の名前」「犬の年齢」「仕事」「好きな食べ物」のような短い見出し。本人以外（ペット・家族）の事実は必ず誰のことかを key に入れる（×年齢 ○犬の年齢）。同じ見出しは覚えている記憶と揃える。
- value は短い値（例: 柴犬、ポチ）。quote は根拠になった相手の発言をそのまま短く抜き出す。
- text は後で読んで分かる短い文（例: 柴犬を飼っていて名前はポチ）。
- 住所・連絡先・お金・宗教・政治・性的な話は抜き出さない（健康や恋愛の話は抜き出してよい）。
- unknown には、この話題で相手に聞くと自然な、まだ知らないこと（例: 犬の名前、犬種）を最大2つ。
JSONだけを返す。"""


async def extract_facts(llm: OllamaClient | None, text: str, recent_player: list[str],
                        memory: MemoryStore) -> tuple[list[MemoryFact], list[str]]:
    if llm is None:
        return keyword_facts(text), []
    known = "\n".join(f"- {f.key}: {f.value}" for f in memory.facts[-20:]) or "なし"
    ctx = "\n".join(f"相手: {t}" for t in recent_player[-3:])
    out = await llm.chat_json(EXTRACT_SYSTEM, [{"role": "user", "content":
                              f"[覚えている記憶]\n{known}\n[直近の相手の発言]\n{ctx}\n[今の相手の発言]\n{text}"}],
                              EXTRACT_SCHEMA, temperature=0.0, num_predict=300)
    if not out:
        return keyword_facts(text), []
    source = " ".join(recent_player[-3:] + [text])
    facts = [f for f in (_to_fact(x) for x in out.get("facts", [])) if f and accept_fact(f, source)]
    # LLM の取りこぼしを規則で補う（名前など）
    keys = {f.key for f in facts}
    facts += [f for f in keyword_facts(text, recent_player) if f.key not in keys and f.value not in {x.value for x in facts}]
    unknown = [u for u in out.get("unknown", []) if isinstance(u, str) and 0 < len(u) <= 20][:2]
    return facts, unknown


def _to_fact(x: dict) -> MemoryFact | None:
    try:
        key, value = str(x["key"]).strip(), str(x["value"]).strip()
    except (KeyError, TypeError):
        return None
    topic = x.get("topic") if x.get("topic") in TOPICS else "other"
    return MemoryFact(key=key[:20], value=value[:30], topic=topic, text=str(x.get("text", ""))[:60],
                      quote=str(x.get("quote", ""))[:60])


def accept_fact(f: MemoryFact, player_text: str) -> bool:
    """保存してよいか: 値が相手の発言に実際に出てくる／機微情報でない／長すぎない。"""
    if not f.key or not f.value or len(f.value) > 30:
        return False
    if SENSITIVE.search(f.key + f.value + f.text + f.quote):
        return False
    norm = lambda s: re.sub(r"\s", "", s)  # noqa: E731
    return norm(f.value) in norm(player_text)


_PET = re.compile(r"(犬|猫|うさぎ|ハムスター|インコ|金魚)")


_NAME = re.compile(r"名前は[「『]?([ぁ-んァ-ヶー一-龠A-Za-z]{1,10}?)[」』]?(?:[。、！!？?\s]|です|だよ|って|$)")


def keyword_facts(text: str, recent: list[str] | None = None) -> list[MemoryFact]:
    """規則での最低限: ペットを飼っていること、ペットの名前。"""
    if SENSITIVE.search(text):
        return []
    out = []
    ctx = " ".join((recent or [])[-3:] + [text])
    m = _PET.search(text)
    if m and re.search(r"飼|うちの|散歩", text):
        out.append(MemoryFact(key="ペット", value=m.group(1), topic="pet", text=f"{m.group(1)}を飼っている", quote=text[:60]))
    pet = _PET.search(ctx)
    n = _NAME.search(text)
    if n and pet:
        out.append(MemoryFact(key=f"{pet.group(1)}の名前", value=n.group(1), topic="pet",
                              text=f"{pet.group(1)}の名前は{n.group(1)}", quote=text[:60]))
    return out
