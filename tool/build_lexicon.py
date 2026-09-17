"""assets/lexicon/*.json を作る。
元データ（tool/lexicon_src、git 管理外）: 東北大 評価極性辞書 / JMdict (jmdict-simplified) / Sudachi synonyms.txt / pymlask の emotions・emotemes
- shogi_terms.json: tool/shogi_terms.src.json を正規化して出力
- sentiment_ja.json: 東北大 日本語評価極性辞書（用言編・名詞編）から単語→極性(+1/-1)
  出典: 小林ら(2005)「意見抽出のための評価表現の収集」自然言語処理12(3) / 東山ら(2008) 言語処理学会第14回年次大会
使い方: python tool/build_lexicon.py （tool/lexicon_src に元ファイル）
"""
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tool" / "lexicon_src"
OUT = ROOT / "assets" / "lexicon"
KANJI = re.compile(r"[一-鿿]")


def norm(s: str) -> str:
    """Dart の normalizeJa と同じ規則: NFKC 相当の一部 + カタカナ→ひらがな + 小文字化 + 空白除去。"""
    s = unicodedata.normalize("NFKC", s).lower()
    s = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)
    return re.sub(r"\s+", "", s)


def stems(word: str, pos: str) -> list[str]:
    if not word or " " in word:
        return []
    out = [word]
    if word.endswith("い") and len(word) >= 3 and KANJI.search(word):  # 形容詞: 強い→強
        out.append(word[:-1])
    elif word[-1] in "うくぐすつぬぶむる" and len(word) >= 3 and KANJI.search(word[:-1]):  # 動詞: 負ける→負け
        out.append(word[:-1])
    return out


INSULT_GLOSS = re.compile(r"\b(fool|idiot|stupid|moron|dunce|dumb|incompetent|unskilled|amateur|novice|coward|loser|weakling|"
                          r"good-for-nothing|blockhead|bumpkin|clumsy|useless|clown|braggart|show-off|big-mouth|wimp|chicken)\b", re.I)
ABUSE_STOP = {"きさま", "貴様", "おっさん", "おばさん", "おやじ", "ばばあ", "ちょっかい", "ほざく", "やがる", "くたばる", "ミーハー",
              "スローモー", "エコノミックアニマル", "ピザ", "シュガー", "ハーモニカ", "丸太", "共", "玉", "猿", "芋", "夷"}
MOCK_STOP = {"じゃこ", "肩書", "素人", "新米", "初心者", "新人", "未熟", "百姓", "禿げ", "老耄"}


def forms(w):
    """漢字表記があれば漢字のみ（かな読みは同音の普通語と誤爆するため）。かなのみの語は5文字以上のかなも使う。"""
    kanji = [k["text"] for k in w.get("kanji", [])]
    kana = [k["text"] for k in w.get("kana", [])]
    out = kanji if kanji else [k for k in kana if len(k) >= 4]
    return [f for f in out if not re.search(r"[0-9a-zA-Z０-９]", f)]


def ok_len(t: str) -> bool:
    kana_only = re.fullmatch(r"[\u3040-\u30ff\u30fc]+", t) is not None
    return len(t) >= (3 if kana_only else 2)


def load_jmdict():
    """JMdict（CC BY-SA 4.0, EDRDG）から不適切語・けなし語・将棋分野語を抽出。"""
    path = next(SRC.glob("jmdict-eng-*.json"), None)
    if path is None:
        return [], [], []
    d = json.loads(path.read_text(encoding="utf-8"))
    abuse, mock, shogi = set(), set(), set()
    for w in d["words"]:
        fs = [f for f in forms(w) if ok_len(f)]
        senses = w["sense"]
        if any("shogi" in sn.get("field", []) for sn in senses):
            shogi.update(fs)
        # 多義語（ふつうの意味もある語）は不適切・けなしに入れない
        if not all(set(sn.get("misc", [])) & {"vulg", "X", "derog"} for sn in senses):
            continue
        for sense in senses:
            misc = set(sense.get("misc", []))
            gloss = " ".join(g["text"] for g in sense.get("gloss", []))
            if "vulg" in misc or "X" in misc:
                abuse.update(f for f in fs if f not in ABUSE_STOP)
            elif "derog" in misc:
                if INSULT_GLOSS.search(gloss):
                    mock.update(f for f in fs if f not in MOCK_STOP and f not in ABUSE_STOP)
                elif re.search(r"(ethnic|racial|discriminat|slur|prostitut|homosexual|disabled|cripple|retard|insane|madman)", gloss, re.I):
                    abuse.update(f for f in fs if f not in ABUSE_STOP)
    return sorted(abuse), sorted(mock - abuse), sorted(shogi)


def load_sudachi_groups():
    """Sudachi 同義語辞書（Apache-2.0）: グループ番号 → 見出し語（対訳・誤用は除く）。"""
    path = SRC / "sudachi_synonyms.txt"
    groups: dict[str, list[str]] = {}
    if not path.exists():
        return groups
    for line in path.read_text(encoding="utf-8").splitlines():
        f = line.split(",")
        if len(f) < 9 or not f[0].isdigit():
            continue
        if f[4] in ("1", "4"):  # 1=対訳（英語など） 4=誤用
            continue
        groups.setdefault(f"{f[0]}-{f[3]}", []).append(f[8])  # 同じ語彙素（表記ゆれ・略語・別称）だけをまとめる
    return groups


def load_mlask():
    """ML-Ask 感情語辞書（BSD-3-Clause, Ptaszynski ら / Ikegami）: 語 → 感情、強調表現。"""
    base = SRC / "mlask"
    emotions: dict[str, str] = {}
    if not base.exists():
        return emotions, []
    for emo in ("yorokobi", "suki", "yasu", "iya", "ikari", "aware", "kowa", "haji", "odoroki", "takaburi"):
        p = base / f"{emo}.txt"
        if p.exists():
            for w in p.read_text(encoding="utf-8").splitlines():
                w = norm(w.strip())
                if len(w) >= 2 and w not in emotions:
                    emotions[w] = emo
    inten = []
    for name in ("gitaigo", "interjections"):
        p = base / f"emoteme_{name}_uncoded.txt"
        if p.exists():
            inten += [norm(x.strip()) for x in p.read_text(encoding="utf-8").splitlines() if len(x.strip()) >= 3]
    inten += ["めっちゃ", "めちゃくちゃ", "超", "マジで", "ほんとに", "本当に", "すごく", "とても", "かなり", "死ぬほど", "クソ", "ガチで"]
    return emotions, sorted({norm(x) for x in inten})


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pos: dict[str, float] = {}
    for line in (SRC / "wago.121808.pn").read_text(encoding="utf-8").splitlines():
        if "\t" not in line:
            continue
        tag, w = line.split("\t", 1)
        v = 1.0 if tag.startswith("ポジ") else -1.0
        for s in stems(w.strip(), "v"):
            s = norm(s)
            if len(s) >= 2:
                pos[s] = pos.get(s, 0) + v
    for line in (SRC / "pn.csv.m3.120408.trim").read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or parts[1] not in ("p", "n"):
            continue
        w = norm(parts[0].strip('"'))
        if len(w) >= 2 and not re.fullmatch(r"[0-9%,.]+", w):
            pos[w] = pos.get(w, 0) + (1.0 if parts[1] == "p" else -1.0)
    sentiment = {k: (1 if v > 0 else -1) for k, v in pos.items() if v != 0}
    (OUT / "sentiment_ja.json").write_text(json.dumps(sentiment, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    src = json.loads((ROOT / "tool" / "shogi_terms.src.json").read_text(encoding="utf-8"))
    out = {"version": 2, "terms": [], "request": {}, "accept": [], "decline": [], "pieces": [], "shogiContext": []}
    groups = load_sudachi_groups()
    head_index: dict[str, list[str]] = {}
    for gid, words in groups.items():
        for w in words:
            head_index.setdefault(norm(w), []).append(gid)
    seen = set()
    stats = {"sudachi": 0, "jmdict_abuse": 0, "jmdict_mock": 0}
    for kind in ("blunderCall", "hangingPiece", "threat", "mock", "praise", "question", "abuse"):
        for e in list(src[kind]):
            seen.add(norm(e["t"]))
            if kind in ("abuse", "question"):
                continue
            for gid in head_index.get(norm(e["t"]), []):
                if len(groups[gid]) > 12:
                    continue
                for syn in groups[gid]:
                    n = norm(syn)
                    if n not in seen and ok_len(syn) and n not in ("こわい", "へた"):
                        seen.add(n)
                        src[kind].append({"t": syn, "w": round(e["w"] * 0.85, 2), "src": "sudachi"})
                        stats["sudachi"] += 1
    abuse, mock, shogi = load_jmdict()
    for t in abuse:
        if norm(t) not in seen:
            seen.add(norm(t)); src["abuse"].append({"t": t, "w": 1, "src": "jmdict"}); stats["jmdict_abuse"] += 1
    for t in mock:
        if norm(t) not in seen:
            seen.add(norm(t)); src["mock"].append({"t": t, "w": 0.8, "src": "jmdict"}); stats["jmdict_mock"] += 1
    out["shogiContext"] = sorted({norm(t) for t in shogi if len(norm(t)) >= 2})
    print(stats, "shogiContext", len(out["shogiContext"]))
    for kind in ("blunderCall", "hangingPiece", "threat", "mock", "praise", "question", "abuse"):
        for e in src[kind]:
            # 不適切語はカタカナのまま照合（「カス」を「動かす」に誤爆させない）
            t = norm(e["t"]) if kind != "abuse" else unicodedata.normalize("NFKC", e["t"]).lower()
            out["terms"].append({"t": t, "k": kind, "w": e["w"], **({"neg": True} if e.get("neg") else {}),
                                 **({"raw": True} if kind == "abuse" else {})})
    out["request"] = {k: [norm(x) for x in v] for k, v in src["request"].items()}
    out["accept"] = [norm(x) for x in src["accept"]]
    out["decline"] = [norm(x) for x in src["decline"]]
    out["pieces"] = [norm(x) for x in src["pieces"]]
    (OUT / "shogi_terms.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    emotions, inten = load_mlask()
    (OUT / "emotion_ja.json").write_text(json.dumps({"words": emotions, "intensifiers": inten}, ensure_ascii=False,
                                                    separators=(",", ":")), encoding="utf-8")
    print("emotions", len(emotions), "intensifiers", len(inten))
    print("sentiment", len(sentiment), "terms", len(out["terms"]))


if __name__ == "__main__":
    main()
