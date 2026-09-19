"""Dart の fact_guard.dart と同じ見方で、手書きのセリフを誤って弾かないか確かめる。

実機で「口調は通るが中身が事実と違う」セリフが出たので、生成側に検査を足した。
ただし厳しすぎると、賢太郎さんが書いた正しいセリフまで落ちる。
527件に当ててみて、引っかかる行を見てから加減を決める。
"""
import json
import re
import sys

FACTS_WIN = re.compile(r"相手が投了|相手玉が詰み|私の勝ち|勝利")
FACTS_LOSE = re.compile(r"私が投了|私の玉が詰み|敗北|私の負け")
SAYS_LOST = re.compile(r"参りました|負けました|私の負け|降参|敗北")
SAYS_WON = re.compile(r"私の勝ち|勝利でござい|勝ちました")
FACTS_BAD = re.compile(r"悪手|点損")
SAYS_BEST = re.compile(r"最善(の手|手)?(で|だ|です|でござい)")


def check(line: str, facts: str) -> list[str]:
    out = []
    if FACTS_WIN.search(facts) and SAYS_LOST.search(line):
        out.append("勝っているのに負けを認めている")
    if FACTS_LOSE.search(facts) and SAYS_WON.search(line):
        out.append("負けているのに勝ちを名乗っている")
    # 事実の側も「最善」と言っているなら言い張りではない（最善手でも損をすることはある）
    if FACTS_BAD.search(facts) and "最善" not in facts and SAYS_BEST.search(line):
        out.append("悪手を最善と言っている")
    return out


rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
hits = []
for r in rows:
    v = check(r["line"], r["facts"])
    if v:
        hits.append(f"{r['id']}  {','.join(v)}\n    事実: {r['facts']}\n    セリフ: {r['line']}")
out = [f"rows={len(rows)}  引っかかった {len(hits)}件", ""] + hits
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
