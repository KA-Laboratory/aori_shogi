"""事実の残りの不揃いを直す（2026-09-19、3周目）。

tools/probe_appshape.py で場面ごとにアプリの型と突き合わせたら、まだ21件ずれていた。
全角の「形勢＝」と誤字（形拡・形応）のせいで、それまでの検査をすり抜けていた分。

- question_dodge 6件: 全角＝と、アプリが出さない言い方（「不利だが逆転の可能性あり」など）。
  どのセリフも形勢に触れていないので、気分に合う側の1語に置き換える。
- abuse 14件: 形勢が抜けている。アプリは「相手の発言は不適切。形勢=X。」と送る。
  セリフはどれも形勢に触れていない叱り方なので、気分に合う形勢を入れて散らす。
- move 1件: 「形拡=」の誤字。

セリフ（line）には触れない。

  python tools/rewrite_facts2.py            # 差分を見るだけ
  python tools/rewrite_facts2.py --apply
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"

FACTS = {
    # --- question_dodge: セリフはどれも「教えない」だけで形勢に触れていない ---
    "question_dodge-composed-0289": "形勢=互角。相手に読みを聞かれた。教えない。",
    "question_dodge-smug-0290": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    "question_dodge-smug-0292": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    # 「後で大逆転された際の絶望」＝いまは押されている
    "question_dodge-smug-0293": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    "question_dodge-rattled-0298": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    "question_dodge-meltdown-0304": "形勢=劣勢。相手に読みを聞かれた。教えない。",

    # --- abuse: 形勢が抜けていた。気分に合う側へ散らす ---
    "abuse-composed-0034": "相手の発言は不適切。形勢=互角。",
    "abuse-composed-0035": "相手の発言は不適切。形勢=優勢。",
    "abuse-composed-0036": "相手の発言は不適切。形勢=互角。",
    "abuse-smug-0037": "相手の発言は不適切。形勢=優勢。",
    "abuse-smug-0038": "相手の発言は不適切。形勢=優勢。",
    "abuse-smug-0039": "相手の発言は不適切。形勢=互角。",
    "abuse-rattled-0040": "相手の発言は不適切。形勢=劣勢。",
    "abuse-rattled-0041": "相手の発言は不適切。形勢=互角。",
    "abuse-rattled-0042": "相手の発言は不適切。形勢=劣勢。",
    "abuse-meltdown-0043": "相手の発言は不適切。形勢=劣勢。",
    "abuse-meltdown-0044": "相手の発言は不適切。形勢=劣勢。",
    "abuse-coverUp-0045": "相手の発言は不適切。形勢=互角。",
    "abuse-coverUp-0046": "相手の発言は不適切。形勢=優勢。",
    "abuse-coverUp-0047": "相手の発言は不適切。形勢=互角。",

    # --- move: 「形拡=」の誤字。数字と語は噛み合っているのでそのまま ---
    "move-smug-0018": "23手目。形勢=優勢（評価値+2400）。私の手 △左上角銀駒 は悪手で約500点損。",
}


def main() -> None:
    apply = "--apply" in sys.argv
    rows = [json.loads(l) for l in PATH.read_text(encoding="utf-8").splitlines() if l.strip()]
    by_id = {r["id"]: r for r in rows}
    missing = [i for i in FACTS if i not in by_id]
    if missing:
        raise SystemExit(f"見つからない id: {missing}")
    n = 0
    for i, after in FACTS.items():
        r = by_id[i]
        if r["facts"] == after:
            continue
        print(f"{i}\n  - {r['facts']}\n  + {after}\n    セリフ: {r['line']}")
        r["facts"] = after
        n += 1
    # 全角＝や誤字が他に残っていないか
    rest = [r["id"] for r in rows if "形勢＝" in r["facts"] or "形拡" in r["facts"] or "形応" in r["facts"]]
    if rest:
        print(f"\nまだ残っている全角＝・誤字: {rest}")
    print(f"\n{n}件を書き直した" if apply else f"\n{n}件（--apply を付けると書き換える）")
    if apply:
        PATH.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


if __name__ == "__main__":
    main()
