"""残っていた事実を、アプリが実際に送る形に1件ずつ書き直す（2026-09-19）。

normalize_stance.py は言い換えで済む28件を機械的に揃えた。ここで直すのは、
機械では決められなかった残り36件。セリフ（line）は一切いじらず、事実だけを
そのセリフが成り立つ側に寄せる。判断の根拠はこの表のコメントに残す。

アプリが送る形（game_controller.dart の _facts）:
  move     : N手目。形勢=優勢/互角/劣勢（評価値+N）。私の手 △XY駒 は…
  praised  : 形勢=優勢/互角/劣勢。相手に褒められた。      ← 数字は付かない
  question_dodge: 形勢=優勢/互角/劣勢。相手に読みを聞かれた。教えない。

  python tools/rewrite_facts.py          # 差分を見るだけ
  python tools/rewrite_facts.py --apply
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit" / "all.jsonl"

# id -> 書き直したあとの事実
FACTS = {
    # --- praised: セリフが勝ち筋を語っているので優勢、最後まで分からないと言う1件だけ劣勢 ---
    # 「勝負は最後まで何が起こるか分かりませんな」＝まだ苦しい
    "praised-composed-0186": "形勢=劣勢。相手に褒められた（5回目）。",
    # 「盤上構想が結実し始めた」
    "praised-composed-0187": "形勢=優勢。相手に褒められた（2回目）。",
    # 「これぞ大逆転の美学」
    "praised-smug-0192": "形勢=優勢。相手に褒められた3回目。",
    # 「形勢=勝ち、相手に褒められた1回目。」と形が壊れていた3件。緊張・プレッシャーを
    # 口にしているので、勝っている側で間違いない。
    "praised-rattled-0198": "形勢=優勢。相手に褒められた（1回目）。",
    "praised-rattled-0200": "形勢=優勢。相手に褒められた（1回目）。",
    "praised-coverUp-0206": "形勢=優勢。相手に褒められた（1回目）。",
    # 「本当に逆転できているのか不安」＝逆転はしている
    "praised-rattled-0199": "形勢=優勢。相手に褒められた3回目。",
    # 「私の完璧な計算通りの展開」
    "praised-coverUp-0204": "形勢=優勢。相手に褒められた（2回目）。",
    # 「我がシナリオ通り」
    "praised-coverUp-0205": "形勢=優勢。相手に褒められた3回目。",
    # 「奇跡ではなく必然」
    "praised-coverUp-0209": "形勢=優勢。相手に褒められた3回目。",

    # --- question_dodge: セリフが形勢に一切触れていないので、気分に合う側へ振る ---
    # 平静・取り繕いは余裕がある側、動揺・大混乱は苦しい側に置くと気分と噛み合う。
    "question_dodge-composed-0286": "形勢=優勢。相手に読みを聞かれた。教えない。",
    "question_dodge-composed-0287": "形勢=互角。相手に読みを聞かれた。教えない。",
    "question_dodge-composed-0288": "形勢=互角。相手に読みを聞かれた。教えない。",
    "question_dodge-rattled-0295": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    "question_dodge-rattled-0296": "形勢=互角。相手に読みを聞かれた。教えない。",
    "question_dodge-meltdown-0301": "形勢=劣勢。相手に読みを聞かれた。教えない。",
    "question_dodge-coverUp-0305": "形勢=優勢。相手に読みを聞かれた。教えない。",
    "question_dodge-coverUp-0307": "形勢=互角。相手に読みを聞かれた。教えない。",
    "question_dodge-coverUp-0309": "形勢=優勢。相手に読みを聞かれた。教えない。",

    # --- move: 「評価値±N」の符号を決める。形勢の言葉と数字が噛み合わない分も揃える ---
    # セリフが形勢を口にしている行は、その言葉を動かさず数字の方を桁で合わせる。
    # セリフが形勢に触れていない行は、数字を残して言葉の方を +300/-300 の規則に合わせる。
    "move-smug-0014": "23手目。形勢=互角（評価値+50）。私の手 △７八飛 は最善。",
    # ±400 は互角の範囲(±300未満)を超える。セリフが強気なので優勢側に。
    "move-smug-0015": "57手目。形勢=優勢（評価値+400）。私の手 △６六桂 は最善。",
    # セリフが「評価値は互角」と言っている
    "move-rattled-0020": "18手目。形勢=互角（評価値+50）。私の手 △7六歩 は最善。",
    "move-rattled-0022": "12手目。形勢=優勢（評価値+500）。私の手 △8八銀 は最善。",
    "move-rattled-0023": "34手目。形勢=劣勢（評価値-1000）。私の手 △2七歩 は悪手で約80点損。",
    "move-rattled-0024": "45手目。形勢=優勢（評価値+300）。私の手 △9七角 は最善。",
    "move-rattled-0025": "78手目。形勢=優勢（評価値+400）。私の手 △7七金 は最善。",
    "move-rattled-0026": "100手目。形勢=劣勢（評価値-900）。私の手 △1七歩 は悪手で約90点損。",
    # ±200 は互角の範囲。セリフは形勢に触れていないので言葉を互角に。
    "move-rattled-0027": "111手目。形勢=互角（評価値+200）。私の手 △8六金 は最善。",
    # セリフが「この互角の展開」と言っているので互角のまま、数字を範囲内に。
    "move-rattled-0028": "15手目。形勢=互角（評価値+120）。私の手 △飛4駒 は悪手で約100点損。",
    # セリフが「優勢を保つため」
    "move-rattled-0029": "8手目。形勢=優勢（評価値+3100）。私の手 △玉前駒 は悪手で約300点損。",
    # 「形応=」と誤字になっていた。セリフは「これほど劣勢に」。
    "move-rattled-0030": "17手目。形勢=劣勢（評価値-2900）。私の手 △香車駒 は悪手で約280点損。",
    # セリフが「この互角の盤面」
    "move-rattled-0031": "10手目。形勢=互角（評価値+150）。私の手 △銀8駒 は悪手で約130点損。",
    "move-meltdown-0038": "12手目。形勢=劣勢（評価値-2700）。私の手 △角6駒 は悪手で約250点損。",
    # セリフは形勢に触れず「しまったな」。大混乱で互角は噛み合わないので劣勢に。
    "move-meltdown-0039": "15手目。形勢=劣勢（評価値-1200）。私の手 △飛4駒 は悪手で約180点損。",
    "move-meltdown-0040": "8手目。形勢=劣勢（評価値-3100）。私の手 △金7駒 は悪手で約300点損。",
    "move-meltdown-0041": "18手目。形勢=劣勢（評価値-2600）。私の手 △歩7駒 は悪手で約240点損。",
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
    print(f"\n{n}件を書き直した" if apply else f"\n{n}件（--apply を付けると書き換える）")
    if apply:
        PATH.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


if __name__ == "__main__":
    main()
