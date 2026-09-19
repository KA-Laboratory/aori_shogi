"""褒められた場面の事実を、アプリが実際に送る形に直す（2026-09-19）。

アプリ（game_controller.dart の _facts と _receiveTaunt）:
  praised          : 形勢=優勢/互角/劣勢。相手に褒められた（N回目）。  ← N は 1 か 2 だけ
                     （praiseStreak が 3 以上になると別の合図に切り替わるため）
  praiseFlood /
  praise_suspicious: 相手にN回続けて褒められた。                      ← 形勢は付かない

学習データはここが揃っていなかった:
- praised に「5回目」「8回目」がある。その組み合わせはアプリから絶対に来ない。
- praise_suspicious に「（4回以上）」という雛形の注記が残っている。回数が無い行もある。
- praised に（評価値+100）が付いている行がある。この場面にアプリは数字を付けない。

セリフ（line）には一切触れない。回数を 1 か 2 に落とすのは、どのセリフも
「何度も褒められた」と言っていない行だけ。言っている3件は praise_suspicious に移す。

  python tools/rewrite_praise.py            # 差分を見るだけ
  python tools/rewrite_praise.py --apply
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"

# セリフが評価値そのものを口にしており（「評価は+20と確信している」）、
# アプリはこの場面に数字を送らない。事実を直すとセリフが宙に浮くので落とす。
DROP = {"praised-rattled-0085"}

# セリフが「何度も褒められた」側を向いている3件。場面を移し、事実を続けての形にする。
TO_SUSPICIOUS = {
    "praised-rattled-0201": "相手に8回続けて褒められた。",
    "praised-rattled-0202": "相手に8回続けて褒められた。",
    "praised-coverUp-0208": "相手に5回続けて褒められた。",
}

# 残りの praised。1回目 = 初めて褒められた手応えのセリフ、2回目 = それ以外。
PRAISED = {
    "praised-composed-0121": ("互角", 1),
    "praised-smug-0122": ("優勢", 2),      # 「ようやく…域に達しましたか」
    "praised-rattled-0123": ("互角", 1),   # 「急に褒められると調子が狂う」
    "praised-meltdown-0124": ("優勢", 2),
    "praised-coverUp-0125": ("互角", 2),
    "praised-composed-0186": ("劣勢", 2),
    "praised-composed-0187": ("優勢", 2),
    "praised-composed-0188": ("互角", 1),
    "praised-composed-0189": ("互角", 1),
    "praised-composed-0190": ("互角", 2),
    "praised-composed-0191": ("互角", 2),
    "praised-smug-0192": ("優勢", 2),
    "praised-smug-0193": ("劣勢", 2),
    "praised-smug-0194": ("劣勢", 2),
    "praised-smug-0195": ("劣勢", 2),
    "praised-smug-0196": ("互角", 2),
    "praised-smug-0197": ("優勢", 1),
    "praised-rattled-0198": ("優勢", 1),
    "praised-rattled-0199": ("優勢", 2),
    "praised-rattled-0200": ("優勢", 1),
    "praised-meltdown-0203": ("優勢", 2),
    "praised-coverUp-0204": ("優勢", 2),
    "praised-coverUp-0205": ("優勢", 2),
    "praised-coverUp-0206": ("優勢", 1),
    "praised-coverUp-0207": ("優勢", 1),
    "praised-coverUp-0209": ("優勢", 2),
}


def fix_suspicious(facts: str) -> str:
    """雛形の注記を外し、回数の無いものに回数を入れ、句点で終わらせる。"""
    f = facts.replace("（4回以上）", "").replace("(4回以上)", "").strip()
    if "何度も褒められている" in f:
        f = "相手に4回続けて褒められた。"
    if not f.endswith("。"):
        f += "。"
    return f


def main() -> None:
    apply = "--apply" in sys.argv
    rows = [json.loads(l) for l in PATH.read_text(encoding="utf-8").splitlines() if l.strip()]
    kept, n = [], 0

    def show(r: dict, before: str, extra: str = "") -> None:
        print(f"{r['id']}{extra}\n  - {before}\n  + {r['facts']}\n    セリフ: {r['line']}")

    for r in rows:
        if r["id"] in DROP:
            print(f"{r['id']}  落とす\n    事実: {r['facts']}\n    セリフ: {r['line']}")
            n += 1
            continue
        before = r["facts"]
        if r["id"] in TO_SUSPICIOUS:
            r["facts"] = TO_SUSPICIOUS[r["id"]]
            r["scene"] = "praise_suspicious"
            show(r, before, "  → praise_suspicious へ")
            n += 1
        elif r["id"] in PRAISED:
            word, times = PRAISED[r["id"]]
            r["facts"] = f"形勢={word}。相手に褒められた（{times}回目）。"
            if r["facts"] != before:
                show(r, before)
                n += 1
        elif r["scene"] == "praise_suspicious":
            r["facts"] = fix_suspicious(before)
            if r["facts"] != before:
                show(r, before)
                n += 1
        kept.append(r)

    left = [r["id"] for r in kept if r["scene"] == "praised"
            and not re.fullmatch(r"形勢=(優勢|互角|劣勢)。相手に褒められた（[12]回目）。", r["facts"])]
    if left:
        print(f"\n形が揃っていない praised: {left}")
    print(f"\n{n}件を直した（{len(rows)} → {len(kept)}）" if apply else f"\n{n}件（--apply で書き換える）")
    if apply:
        PATH.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in kept), encoding="utf-8")


if __name__ == "__main__":
    main()
