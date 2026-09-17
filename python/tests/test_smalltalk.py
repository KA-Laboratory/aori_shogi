import asyncio

from aori_lab import smalltalk as st


class FakeLLM:
    model = "fake"
    last_latency = 0.0
    last_error = None

    def __init__(self, out):
        self.out = out

    async def chat_json(self, *a, **k):
        return self.out


def test_memory_store_upsert_delete(tmp_path):
    m = st.MemoryStore(tmp_path / "mem.json")
    m.upsert(st.MemoryFact(key="犬の名前", value="ポチ", topic="pet", text="犬の名前はポチ"))
    m.upsert(st.MemoryFact(key="犬の名前", value="コタロウ", topic="pet", text="犬の名前はコタロウ"))
    assert len(m.facts) == 1 and m.facts[0].value == "コタロウ" and m.facts[0].mentions == 2
    again = st.MemoryStore(tmp_path / "mem.json")
    assert again.facts[0].value == "コタロウ"
    assert "コタロウ" in again.prompt_block("散歩いってきた")
    assert again.delete(again.facts[0].id) and not again.facts


def test_extract_requires_grounding_and_blocks_sensitive(tmp_path):
    mem = st.MemoryStore(tmp_path / "mem.json")
    llm = FakeLLM({"facts": [
        {"topic": "pet", "key": "犬の種類", "value": "柴犬", "text": "柴犬を飼っている", "quote": "柴犬なんだ"},
        {"topic": "pet", "key": "犬の名前", "value": "ポチ", "text": "名前はポチ", "quote": ""},       # 言っていない
        {"topic": "other", "key": "持病", "value": "腰痛", "text": "腰痛で通院している", "quote": "腰痛"},  # 健康はOK
        {"topic": "place", "key": "住所", "value": "中区", "text": "住所は中区", "quote": "中区"},  # 住所は覚えない
    ], "unknown": ["犬の名前"]})
    facts, unknown = asyncio.run(st.extract_facts(llm, "うちの柴犬なんだ、腰痛で通院してて散歩つらい。住所は中区", [], mem))
    assert [f.value for f in facts] == ["柴犬", "腰痛"]
    assert unknown == ["犬の名前"]


def test_smalltalk_and_ai_question_detection():
    assert st.is_smalltalk("今日犬の散歩一旦だけど疲れた")
    assert not st.is_smalltalk("その角タダじゃない？")
    assert st.asks_if_ai("ねえ、あなたってAIなの？")
    assert not st.asks_if_ai("犬の散歩疲れた")
    assert [f.value for f in st.keyword_facts("犬の散歩疲れた")] == ["犬"]


def test_keyword_name_fallback():
    fs = st.keyword_facts("柴犬で、名前はコタロウ。もう8歳", ["今日犬の散歩疲れた"])
    assert ("犬の名前", "コタロウ") in [(f.key, f.value) for f in fs]
