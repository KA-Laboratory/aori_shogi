"""青空文庫（著作権切れ）吉川英治『三国志』孔明の巻〜五丈原の巻から、孔明周辺の台詞（話者は厳密ではない）から軍師らしい言い回しを抜き出して軍師口調の見本にする。
入力: tool/lexicon_src/aozora/*.zip   出力: python/aori_lab/style/gunshi_quotes.json
実行: python3 tool/extract_gunshi_style.py
"""
import glob
import io
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEAKER_NEAR = re.compile(r"孔明")
# 軍師らしさ（策・敵・勝敗・尊大な一人称や二人称）
CUE = re.compile(r"計|策|敵|兵|軍|勝|謀|陣|予|我|わが|汝|愚|笑止|たわけ|浅慮|不覚|天下|必ず|見よ|知れ")
quotes = []
for zp in sorted(glob.glob(str(ROOT / "tool/lexicon_src/aozora/*.zip"))):
    z = zipfile.ZipFile(zp)
    name = next(n for n in z.namelist() if n.endswith(".txt"))
    text = z.read(name).decode("cp932", errors="ignore")
    text = re.sub(r"《[^》]*》|［＃[^］]*］|｜", "", text)
    title = text.splitlines()[0].strip()
    body = text.split("-------------------------------------------------------", 2)[-1]
    paras = [p.strip() for p in body.splitlines() if p.strip()]
    for i, p in enumerate(paras):
        if not p.startswith("「"):
            continue
        q = p.strip("「」 　")
        if not 12 <= len(q) <= 70 or "「" in q or "」" in q or "※" in q:
            continue
        if not CUE.search(q):
            continue
        # 前後の地の文に孔明がいて、他の人物が主語でない
        ctx = " ".join(paras[max(0, i - 1):i] + paras[i + 1:i + 2])
        if not SPEAKER_NEAR.search(ctx):
            continue
        quotes.append({"text": q, "work": f"吉川英治『三国志』{title}"})
seen, uniq = set(), []
for q in quotes:
    if q["text"] not in seen:
        seen.add(q["text"]); uniq.append(q)
out = ROOT / "python/aori_lab/style/gunshi_quotes.json"
out.parent.mkdir(parents=True, exist_ok=True)
json.dump({"source": "青空文庫（吉川英治『三国志』、著作権保護期間満了）", "quotes": uniq}, open(out, "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
print(len(uniq))
