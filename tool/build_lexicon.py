"""assets/lexicon/*.json を作る。
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
    out = {"version": 1, "terms": [], "request": {}, "accept": [], "decline": [], "pieces": []}
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
    (OUT / "shogi_terms.json").write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
    print("sentiment", len(sentiment), "terms", len(out["terms"]))


if __name__ == "__main__":
    main()
