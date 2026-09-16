"""学習結果の集計レポートと、アプリ反映用の候補ファイル出力。"""
from __future__ import annotations

import json
import math
import time
from collections import defaultdict
from pathlib import Path

from .pool import TauntPool

KIND_JA = {"blunderCall": "悪手の指摘", "hangingPiece": "駒浮きの指摘", "threat": "玉の危険の脅し",
           "mock": "からかい", "praise": "褒め殺し", "none": "煽らない"}


def _ci(k: int, n: int) -> str:
    if n == 0:
        return "-"
    p = k / n
    se = math.sqrt(p * (1 - p) / n)
    return f"{p*100:.0f}%（±{1.96*se*100:.0f}）"


def write_report(pool: TauntPool, data_dir: Path, extra: dict | None = None) -> Path:
    games = []
    gp = data_dir / "games.jsonl"
    if gp.exists():
        games = [json.loads(l) for l in gp.read_text(encoding="utf-8").splitlines() if l.strip()]
    ctrl = [g for g in games if g["control"]]
    tnt = [g for g in games if not g["control"]]
    def wins(gs):
        return sum(1 for g in gs if g["taunter_won"]), sum(1 for g in gs if g["winner"] is not None)
    lines = [f"# 煽り学習レポート", f"更新: {time.strftime('%Y-%m-%d %H:%M')}", ""]
    if extra:
        lines += [f"- {k}: {v}" for k, v in extra.items()] + [""]
    wt, nt = wins(tnt)
    wc, nc = wins(ctrl)
    lines += ["## 勝率（煽り役AIから見て）", "",
              "| 条件 | 局数 | 勝率（95%幅） | 軍師の平均評価損 | 平均手数 |", "|---|---|---|---|---|"]
    for name, gs, w, n in [("煽りあり", tnt, wt, nt), ("煽りなし（対照）", ctrl, wc, nc)]:
        al = sum(g["gunshi_avg_loss"] for g in gs) / len(gs) if gs else 0
        pl = sum(g["plies"] for g in gs) / len(gs) if gs else 0
        lines.append(f"| {name} | {len(gs)} | {_ci(w, n)} | {al:.0f}cp | {pl:.0f} |")
    lines.append("")

    # 種類×図星×形勢
    lines += ["## 煽りの種類ごとの効果（平均報酬）", "",
              "報酬 = 冷静さの低下 + 焦りの上昇 + 次の軍師の手の評価損/300（最大1.5） ± 勝敗0.3", "",
              "| 種類 | 図星 | 形勢 | 回数 | 平均報酬 |", "|---|---|---|---|---|"]
    rows = []
    for key, (n, s) in pool.bucket_stats.items():
        kind, truth, stance = key.split("|")
        rows.append((kind, truth, stance, n, s / n if n else 0))
    for kind, truth, stance, n, m in sorted(rows, key=lambda r: -r[4]):
        if n >= 3:
            lines.append(f"| {KIND_JA.get(kind, kind)} | {truth} | {stance} | {n} | {m:.3f} |")
    lines.append("")

    # 文句ランキング
    lines += ["## よく効いた文句（使用5回以上、平均報酬順）", ""]
    by_kind = defaultdict(list)
    for e in pool.entries.values():
        if e.usable:
            by_kind[e.kind].append(e)
    for kind, es in by_kind.items():
        used = sorted([e for e in es if e.n >= 5], key=lambda e: -e.mean)
        lines.append(f"### {KIND_JA.get(kind, kind)}（プール {len(es)} 件、使用 {len(used)} 件）")
        for e in used[:8]:
            j = e.judgement
            lines.append(f"- {e.mean:+.3f}（{e.n}回, 刺さり {j.sting_if_true}/{j.sting_if_false}, 逆効果 {j.backfire}）「{e.text}」")
        if len(used) > 8:
            lines.append("- …効かなかった例: " + " / ".join(f"「{e.text}」({e.mean:+.2f})" for e in used[-3:]))
        lines.append("")
    judged = [e for e in pool.entries.values() if e.judgement]
    if judged:
        agree = sum(1 for e in judged if e.judge_agrees)
        lines += [f"## 生成意図と採点者の分類の一致率: {agree}/{len(judged)}（{agree/len(judged)*100:.0f}%）", ""]
    rejected = [e for e in pool.entries.values() if e.judgement and not e.judgement.appropriate]
    lines += [f"## 不適切判定で除外: {len(rejected)} 件", ""]
    lines += [f"- 「{e.text}」" for e in rejected[:10]]
    out = data_dir / "report.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def export_candidates(pool: TauntPool, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    usable = [e for e in pool.entries.values() if e.usable]
    ranked = sorted(usable, key=lambda e: -((e.reward_sum + 2 * e.prior()) / (e.n + 2)))
    taunts = defaultdict(list)
    for e in ranked:
        taunts[e.kind].append({"text": e.text, "n": e.n, "mean": round(e.mean, 3), "prior": round(e.prior(), 3),
                               "sting_if_true": e.judgement.sting_if_true, "sting_if_false": e.judgement.sting_if_false,
                               "backfire": e.judgement.backfire})
    (out_dir / "taunts_ranked.json").write_text(json.dumps(taunts, ensure_ascii=False, indent=1), encoding="utf-8")
    # 軍師セリフ候補（assets/lines/gunshi_lines.json と同じ形）
    lines = {"rattled": {"taunt_hit": []}, "meltdown": {"taunt_hit": []}, "smug": {"taunt_miss": []},
             "composed": {"taunt_miss": []}}
    for e in ranked:
        j = e.judgement
        if j.hit_line and 6 <= len(j.hit_line) <= 60:
            (lines["meltdown"] if j.sting_if_true >= 8 else lines["rattled"])["taunt_hit"].append(j.hit_line)
        if j.miss_line and 6 <= len(j.miss_line) <= 60:
            (lines["smug"] if j.backfire >= 5 else lines["composed"])["taunt_miss"].append(j.miss_line)
    for mood in lines.values():
        for k in mood:
            seen, uniq = set(), []
            for s in mood[k]:
                if s not in seen:
                    seen.add(s)
                    uniq.append(s)
            mood[k] = uniq[:60]
    (out_dir / "gunshi_lines_candidates.json").write_text(json.dumps(lines, ensure_ascii=False, indent=1), encoding="utf-8")
    # 分類器の学習データ（文 → 採点者が付けた種類）
    ds = [{"text": e.text, "kind": e.intended_kind, "judge_kind": e.judgement.kind, "agree": e.judge_agrees}
          for e in pool.entries.values() if e.judgement]
    (out_dir / "classifier_dataset.jsonl").write_text("\n".join(json.dumps(d, ensure_ascii=False) for d in ds) + "\n",
                                                      encoding="utf-8")
    return {"taunts": sum(len(v) for v in taunts.values()), "lines": sum(len(x) for m in lines.values() for x in m.values()),
            "dataset": len(ds)}
