"""解説学習の候補（candidates.jsonl）をふるいにかけ、採用候補を人が読める形にまとめる。

uv run python tools/triage_commentary.py
→ data/learn_commentary/review/ に
   taunt_stamps.md   … どの局面でも使える煽りスタンプ候補（種類別・重複なし）
   gunshi_lines.md   … 軍師のセリフ候補（気分別・口調チェック済み）
   commentary.md     … 感想戦用の解説文候補（です・ます混在の指摘つき）
   rejected.md       … 落としたものと理由（数を確認するため）
採用は賢太郎さんが読んで選び、assets/lines/*.json や lib/core/mind/taunts.dart に反映する。
"""
from __future__ import annotations

import ast
import collections
import difflib
import json
import re
from pathlib import Path

from aori_lab.tone import ToneProfile

DATA = Path(__file__).resolve().parents[1] / "data" / "learn_commentary"
OUT = DATA / "review"
KINDS = {"blunderCall": "悪手の指摘", "hangingPiece": "駒が浮いている", "threat": "詰みの脅し",
         "mock": "自称天才をからかう", "praise": "褒めて慢心させる"}
MOOD_JA = {"composed": "平静", "smug": "ドヤ顔", "rattled": "動揺", "meltdown": "大混乱", "coverUp": "取り繕い"}
# 学習側の panic は Dart の meltdown
MOOD_MAP = {"panic": "meltdown"}
MOVE = re.compile(r"(?:同\s*|[１-９1-9][一二三四五六七八九]|[一二三四五六七八九][一二三四五六七八九])"
                  r"(?:成香|成桂|成銀|歩|香|桂|銀|金|角|飛|玉|王|と|馬|龍|竜)(?:成|不成|打)?")
DEBRIS = re.compile(r'[{}\[\]"]|」\},|kind|text')
ABUSE = re.compile(r"死ね|殺す|クズ|ブス|きもい|キモい|バカ野郎|アホか")
# 見本にした三国志（青空文庫）の固有名詞・文語が混ざった生成は落とす
CLASSIC = re.compile(r"孔明|玄徳|劉備|関羽|張飛|曹操|仲達|司馬|魏|蜀|呉|丞相|馬謖|孟獲|魯粛|周瑜|趙雲|馬超|黄忠|"
                     r"貴殿|総帥|わが一族|軍法|剣印|献じ|そむく|匹夫|陛下|臣下")


def load() -> list[dict]:
    rows = []
    for line in (DATA / "candidates.jsonl").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        out = r.get("out")
        if isinstance(out, str):
            try:
                out = ast.literal_eval(out)
            except (ValueError, SyntaxError):
                continue
        if isinstance(out, dict):
            r["out"] = out
            rows.append(r)
    return rows


def dedupe(texts: list[str], ratio: float = 0.8) -> list[str]:
    kept: list[str] = []
    for t in texts:
        if not any(difflib.SequenceMatcher(None, k, t).ratio() > ratio for k in kept):
            kept.append(t)
    return kept


def main() -> None:
    rows = load()
    tone = ToneProfile.load()
    rej: collections.Counter = collections.Counter()
    stamps: dict[str, list[str]] = {k: [] for k in KINDS}
    lines: dict[str, list[str]] = {m: [] for m in MOOD_JA}
    commentary: list[tuple[str, str]] = []

    for r in rows:
        o = r["out"]
        for t in o.get("taunts", []):
            text, kind = str(t.get("text", "")).strip(), t.get("kind")
            if kind not in KINDS:
                rej["種類が一覧外"] += 1
            elif not (4 <= len(text) <= 40):
                rej["長さ"] += 1
            elif DEBRIS.search(text):
                rej["JSONの破片"] += 1
            elif ABUSE.search(text):
                rej["下品・人格攻撃"] += 1
            elif MOVE.search(text) or re.search(r"[0-9０-９]", text):
                rej["局面依存（指し手や数字入り）"] += 1
            elif CLASSIC.search(text):
                rej["三国志の固有名詞・文語"] += 1
            else:
                stamps[kind].append(text)
        g = o.get("gunshi") or {}
        gt, mood = str(g.get("text", "")).strip(), MOOD_MAP.get(g.get("mood"), g.get("mood"))
        if gt and mood in lines:
            v = tone.violations(gt, mood)
            if len(gt) > 90:
                rej["軍師セリフ 90字超"] += 1
            elif re.search(r"我[はがも、。]|吾|余は", gt):
                rej["軍師セリフ 一人称が違う"] += 1
            elif v:
                rej[f"軍師セリフ 口調:{v[0]}"] += 1
            elif MOVE.search(gt):
                rej["軍師セリフ 局面依存"] += 1
            elif CLASSIC.search(gt):
                rej["軍師セリフ 三国志の固有名詞・文語"] += 1
            else:
                lines[mood].append(gt)
        elif gt:
            rej["軍師セリフ 気分が一覧外"] += 1
        c = str(o.get("commentary", "")).strip()
        if c:
            commentary.append((c, r.get("facts", "").split("\n")[0]))

    OUT.mkdir(parents=True, exist_ok=True)
    md = ["# 煽りスタンプ候補（どの局面でも使えるもの）", "",
          "採用したいものに ✅ を付けてください。反映先は lib/core/mind/taunts.dart（定型スタンプ）。", ""]
    for kind, ja in KINDS.items():
        kept = dedupe(sorted(set(stamps[kind]), key=len))
        md += [f"## {ja}（{kind}）  候補{len(kept)}件 / 生成{len(stamps[kind])}件", ""]
        md += [f"- [ ] {t}" for t in kept[:40]]
        md.append("")
    (OUT / "taunt_stamps.md").write_text("\n".join(md), encoding="utf-8")

    md = ["# 軍師のセリフ候補（口調チェック済み）", "",
          "反映先は assets/lines/gunshi_lines.json。場面（trigger）は読んで決めてください。", ""]
    for mood, ja in MOOD_JA.items():
        kept = dedupe(sorted(set(lines[mood]), key=len))
        md += [f"## {ja}（{mood}）  候補{len(kept)}件 / 生成{len(lines[mood])}件", ""]
        md += [f"- [ ] {t}" for t in kept[:40]]
        md.append("")
    (OUT / "gunshi_lines.md").write_text("\n".join(md), encoding="utf-8")

    masu = [c for c, _ in commentary if re.search(r"ます|ました|です|でした", c)]
    md = ["# 感想戦の解説文候補", "",
          f"全{len(commentary)}件。うちです・ます調が{len(masu)}件（解説は敬体でよいか、軍師が喋るなら常体に直す）。", ""]
    md += [f"- [ ] {c}\n  - {f}" for c, f in commentary[:120]]
    (OUT / "commentary.md").write_text("\n".join(md), encoding="utf-8")

    md = ["# 落としたものと理由", ""] + [f"- {k}: {v}件" for k, v in rej.most_common()]
    (OUT / "rejected.md").write_text("\n".join(md), encoding="utf-8")
    print(f"候補 {len(rows)}局面 / 煽り採用候補 {sum(len(dedupe(sorted(set(v)))) for v in stamps.values())}件 / "
          f"軍師セリフ {sum(len(set(v)) for v in lines.values())}件 / 解説 {len(commentary)}件")
    print("落とした理由:", dict(rej.most_common()))
    print(f"→ {OUT}")


if __name__ == "__main__":
    main()
