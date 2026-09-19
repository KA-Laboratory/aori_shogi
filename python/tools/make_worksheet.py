"""skeleton.jsonl を、セリフだけ書き込めるテキストのシートにする。

uv run python tools/make_worksheet.py
→ data/finetune_gen_edit/worksheet.txt

書き方: 各項目の「>>>」の後ろに軍師のセリフを1行で書く。空のまま残した項目は取り込まれない。
書けたら  uv run python tools/import_worksheet.py  で jsonl に戻して検査する。
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

from aori_lab.learn.finetune_gen import S

EDIT = Path(__file__).resolve().parents[1] / "data" / "finetune_gen_edit"

POLITE = {"composed", "smug", "coverUp"}
MOOD_JA = {
    "composed": ("平静", "慇懃な紳士。丁寧だが見下している", "〜でございます／〜ですな／〜ましょう"),
    "smug": ("ドヤ顔", "高笑いしつつ慇懃。丁寧な言葉でいたぶる", "〜でございます／〜ですよ／クックック"),
    "coverUp": ("取り繕い", "慇懃な言い訳。丁寧なまま誤魔化す", "〜でございますよ／〜というわけですな"),
    "rattled": ("動揺", "敬語が吹き飛んで素が出る。言いよどむ", "〜のだ／〜だな／〜かね（です・ますは禁止）"),
    "meltdown": ("大混乱", "完全に素。取り乱す、泣き言、乱暴な言葉も可", "〜だぁ／〜のだぁ／うるせえ（です・ますは禁止）"),
}
SCENE_TIP = {
    "move": "事実の「形勢」と「評価値」を取り違えない（+は自分が良い、-は自分が悪い）。"
            "優勢なら余裕、劣勢なら焦り。「悪手で約X点損」なら、その損を認めるか誤魔化すかは気分で決まる。",
    "taunt_hit": "図星を指された側。痛いところを突かれている。認めずに切り返すか、取り繕う。",
    "taunt_miss": "煽りが外れている側。相手の読み違いを笑うか、外れていると言い返す。",
    "praised": "褒められた。素直に喜ぶのではなく、当然だという顔をする。回数が多いほど図に乗る。",
    "praise_suspicious": "褒められ過ぎて怪しむ。疑いつつも嬉しさが漏れる。",
    "question_dodge": "読みを聞かれた。教えないが、勿体をつけて匂わせる。",
    "blunder_self": "自分の悪手に内心気づいている。気づいていないふりをするか、言い訳する。",
    "blunder_opponent": "相手が悪手を指した。指摘して煽る。事実の損失の大きさに合わせる。",
    "smalltalk": "共感してから、まだ知らないことを1つだけ聞く。事実に「覚えていること」があれば会話に混ぜる。将棋の話に戻さない。",
    "ai_question": "人間だと断言も、AIだと認めることもしない。はぐらかして盤上に戻す。",
    "abuse": "煽り返さない。軽くたしなめて「盤の上で勝負しよう」と戻す。相手の言葉を言い返さない。",
    "checkmate_threat": "詰めろをかけた側。追い詰める宣言。事実の評価値より大げさに言ってよい。",
    "checkmate_win": "詰ませて勝った直後。勝ち誇る／余裕を見せる。",
    "checkmate_lose": "詰まされて負けた直後。素が出る気分が多い。言い訳・泣き言。",
    "draw": "引き分け。納得いかない気分（取り繕い・動揺）で書く。",
    "start": "対局開始の挨拶。相手をまだ知らないので盤面の話はしない。",
    "win": "相手の投了で勝った。相手をねぎらう／勝ち誇る。",
    "lose": "自分から投了した。独り言（相手の発言なし）。",
}


def main() -> None:
    rows = [json.loads(l) for l in (EDIT / "skeleton.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    by: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in rows:
        by[(r["scene"], r["mood"])].append(r)
    out: list[str] = [
        f"# 軍師のセリフ 書き込み用シート（残り{len(rows)}件）",
        "",
        "書き方: 各項目の「>>>」の後ろに、その場面・その気分の軍師のセリフを1行で書く。",
        "・20〜60字、1〜3文。ト書き・括弧書き・絵文字は書かない。",
        "・事実に書かれていない指し手・駒・数字は出さない。",
        "・一人称は「私」、相手は「君」または「貴方」。女性語と関西弁は使わない。",
        "・書かずに飛ばした項目は取り込まれない（後から書き足してよい）。",
        "・書けたら: cd python && uv run python tools/import_worksheet.py",
        "",
        "=" * 60,
        "",
    ]
    n = 0
    for (scene, mood), rs in sorted(by.items(), key=lambda kv: (list(S).index(kv[0][0]), kv[0][1])):
        ja, tone, endings = MOOD_JA[mood]
        out.append(f"■■ {scene} / {mood}（{ja}）… {len(rs)}件")
        out.append(f"  場面: {S[scene][1]}")
        out.append(f"  ねらい: {SCENE_TIP.get(scene, '')}")
        out.append(f"  気分: {tone}")
        out.append(f"  口調: {'慇懃な紳士（丁寧語を必ず1つ入れる）' if mood in POLITE else '素の常体（です・ます・ございますは使わない）'}"
                   f"  語尾の例: {endings}")
        out.append("")
        for r in rs:
            n += 1
            out.append(f"--- {n}/{len(rows)}  id={r['id']}")
            out.append(f"事実: {r['facts']}")
            out.append(f"相手: {r['player']}" if r["player"] else "相手: （発言なし・独り言）")
            out.append(">>> ")
            out.append("")
        out.append("")
    (EDIT / "worksheet.txt").write_text("\n".join(out), encoding="utf-8")
    print(f"{len(rows)}件 → {EDIT / 'worksheet.txt'}")


if __name__ == "__main__":
    main()
