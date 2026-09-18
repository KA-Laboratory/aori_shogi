"""書き込んだ worksheet.txt を jsonl に戻し、その場で口調・事実の検査をする。

uv run python tools/import_worksheet.py [worksheet.txt]
→ data/finetune_gen_edit/edited_by_owner_4.jsonl（書けた分だけ）
  指摘のある行は画面に出す。指摘ゼロになったら
  uv run python tools/merge_owner.py で all.jsonl に足す（または手で足す）。
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.build_edit_set import flags  # noqa: E402
from aori_lab.learn.finetune_gen import Checker  # noqa: E402

EDIT = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"
HEAD = re.compile(r"^---\s+\d+/\d+\s+id=(\S+)")


def parse(text: str) -> dict[str, str]:
    """id → 書かれたセリフ。「>>>」の行（と続く行）を拾う。"""
    out: dict[str, str] = {}
    cur: str | None = None
    buf: list[str] = []
    for raw in text.splitlines():
        m = HEAD.match(raw)
        if m:
            if cur and buf:
                out[cur] = " ".join(buf).strip()
            cur, buf = m.group(1), []
            continue
        if raw.startswith(">>>"):
            buf.append(raw[3:].strip())
        elif buf and raw.strip() and not raw.startswith(("事実:", "相手:", "■", "=", "#", "  ")):
            buf.append(raw.strip())  # 2行目以降に続けて書いた場合
    if cur and buf:
        out[cur] = " ".join(buf).strip()
    return {k: v for k, v in out.items() if v}


def main() -> None:
    sheet = Path(sys.argv[1]) if len(sys.argv) > 1 else EDIT / "worksheet.txt"
    lines = parse(sheet.read_text(encoding="utf-8"))
    skel = {r["id"]: r for r in
            (json.loads(l) for l in (EDIT / "skeleton.jsonl").read_text(encoding="utf-8").splitlines() if l.strip())}
    chk = Checker()
    rows, bad = [], Counter()
    unknown = [i for i in lines if i not in skel]
    for rid, line in lines.items():
        if rid not in skel:
            continue
        r = dict(skel[rid], line=line, source="owner")
        allf = flags(r, chk)
        f = [x for x in allf if "(任意)" not in x]
        hints = [x for x in allf if x.startswith("事実にない駒")]
        r["flags"] = f
        if f:
            bad[f[0]] += 1
            print(f"[{rid}] {','.join(f)}\n    {line}")
        elif hints:
            print(f"[{rid}] ヒント: {','.join(hints)}（事実と違う駒かも。言い回しなら気にしなくてよい）\n    {line}")
        rows.append(r)
    out = EDIT / "edited_by_owner_4.jsonl"
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    left = len(skel) - len(rows)
    print(f"\n書けた {len(rows)}件 / 残り {left}件 → {out}")
    if unknown:
        print(f"※ 雛形に無い id が {len(unknown)}件ありました: {unknown[:5]}")
    if bad:
        print("直したほうがよい点:", dict(bad.most_common()))
    else:
        print("指摘ゼロ。all.jsonl に足してよい状態です。")


if __name__ == "__main__":
    main()
