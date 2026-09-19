"""事実の「形勢=」を、アプリが実際に送る3語（優勢／互角／劣勢）に機械的に揃える。

アプリ（game_controller.dart の _facts）が出す形はこれだけ:
  形勢=優勢/互角/劣勢（評価値+N）
1周目のモデル生成由来の行には「形勢=有利」「形勢=微妙」「形勢=+20」のような、
本番で絶対に来ない言い方が混ざっている。半分がそれだと、数の割に効かない。

直すのは意味が変わらないものだけ:
- 言い換え（有利→優勢、不利→劣勢、均衡→互角 など）
- 数字だけのもの（形勢=+20 → 形勢=互角（評価値+20））
意味が取れないもの（「大きく逆転」「対局は長期」など）は直さず、一覧に出して人が決める。
セリフ（line）には一切手を触れない。

  python tools/normalize_stance.py            # 何が変わるか見るだけ
  python tools/normalize_stance.py --apply    # 書き換える
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"
SAME = {
    "有利": "優勢", "少し有利": "優勢", "僅かに有利": "優勢", "優位": "優勢", "好調": "優勢",
    "不利": "劣勢", "相手が有利": "劣勢",
    "均衡": "互角", "対局は対等": "互角", "微妙": "互角", "安定": "互角",
}
OK = {"優勢", "互角", "劣勢"}


def word_for(ev: int) -> str:
    return "優勢" if ev >= 300 else "劣勢" if ev <= -300 else "互角"


def main() -> None:
    apply = "--apply" in sys.argv
    rows = [json.loads(l) for l in PATH.read_text(encoding="utf-8").splitlines() if l.strip()]
    changed, left = [], []
    for r in rows:
        before = r["facts"]
        m = re.search(r"形勢=([^（(。]+)", before)
        if not m:
            continue
        word = m.group(1).strip()
        if word in OK:
            continue
        after = None
        if word in SAME:
            after = before.replace(f"形勢={word}", f"形勢={SAME[word]}", 1)
        elif re.fullmatch(r"[+\-−]?\d+", word):
            ev = int(word.replace("−", "-").replace("+", ""))
            after = before.replace(f"形勢={word}", f"形勢={word_for(ev)}（評価値{ev:+}）", 1)
        if after:
            changed.append((r["id"], before, after))
            r["facts"] = after
        else:
            left.append((r["id"], before))

    print(f"直せる {len(changed)}件 / 判断が要る {len(left)}件")
    for i, b, a in changed:
        print(f"  {i}\n    - {b}\n    + {a}")
    print("\n[意味が取れないので直さなかった分]")
    for i, b in left:
        print(f"  {i}  {b}")
    if apply:
        PATH.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        print(f"\n→ {PATH} を書き換えた")
    else:
        print("\n（--apply を付けると書き換える）")


if __name__ == "__main__":
    main()
