"""Dart の fact_guard.dart の「事実にない駒／升目」を手書きのセリフに当ててみる。

生成側で弾く検査なので、賢太郎さんが書いた正しいセリフが引っかかるなら厳しすぎる。
"""
import json
import re
import sys

PIECE = re.compile(r"と金|[歩香桂銀金飛角玉馬龍竜]")
NOT_A_PIECE = re.compile(r"馬鹿|歩[くみいけんま]|一歩|角度|玉座|金輪際|金言|飛[びぶんばこ]|香[りばし]")
SQ = re.compile(r"([1-9１-９一二三四五六七八九])([1-9１-９一二三四五六七八九])(?=[歩香桂銀金角飛玉王と馬龍竜成])")
KANJI = {c: str(i) for i, c in enumerate("〇一二三四五六七八九")}
ZEN = str.maketrans("０１２３４５６７８９", "0123456789")


def squares(s: str) -> set[str]:
    return {(KANJI.get(a) or a.translate(ZEN)) + (KANJI.get(b) or b.translate(ZEN)) for a, b in SQ.findall(s)}


def pieces(s: str) -> set[str]:
    return set(PIECE.findall(NOT_A_PIECE.sub("", s)))


rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
sq_hits, pc_hits = [], []
for r in rows:
    line, facts, player = r["line"], r["facts"], r.get("player", "")
    extra_sq = squares(line) - squares(facts) - squares(player)
    if extra_sq:
        sq_hits.append(f"{r['id']}  升目 {sorted(extra_sq)}\n    事実: {facts}\n    セリフ: {line}")
    if "手 " in facts or "私の手" in facts or "相手の手" in facts:
        extra_pc = pieces(line) - pieces(facts) - pieces(player)
        if extra_pc:
            pc_hits.append(f"{r['id']}  駒 {''.join(sorted(extra_pc))}\n    事実: {facts}\n    セリフ: {line}")

out = [f"rows={len(rows)}", f"升目 {len(sq_hits)}件 / 駒 {len(pc_hits)}件", "", "[升目]"] + sq_hits
out += ["", "[駒]"] + pc_hits[:30]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
