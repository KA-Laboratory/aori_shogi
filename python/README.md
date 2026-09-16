# aori_lab — 煽り将棋 Python 版

軍師と**自由文で対話・交渉**しながら指せるブラウザ版と、今後の「AI同士で煽りを学習する」実験場。
感情ロジックは Flutter 版と同じ数値（`shared/mind_vectors.json` で Dart / Python の一致をテスト）。

## 準備（Windows）
```
cd python
powershell -ExecutionPolicy Bypass -File tools\setup_engine.ps1   # やねうら王 V9.00 + Háo を engine\ に配置
uv sync
ollama pull qwen3:8b                                                # 対話用（既定）
```

## 遊ぶ
```
uv run python -m aori_lab.server     →  http://127.0.0.1:8765
```
- 盤をクリックして指す。右のチャットで軍師に何でも話しかけられる（煽り・褒め・待った・ヒント・投了勧告など）。
- 軍師は状況しだいで「一手待ってやろうか？」「さっきの置き直していいか？」「取引しないか？」「引き分けにしないか？」を持ちかける。ボタンでも、チャットで「いいよ」「だめ」でも答えられる。
- 環境変数: `AORI_CHAT_MODEL`（既定 qwen3:8b）、`AORI_NO_LLM=1`（テンプレートのみ）、`AORI_PORT`。

## しくみ
| 担当 | 中身 |
|---|---|
| コード（決定的） | 合法手、エンジン解析、形勢・感情の数値、図星判定、行動が許されるか、行動の効果 |
| LLM（qwen3:8b） | 発言の分類（煽りの種類・要求・強さ）、軍師のセリフ、許可された行動の中からの選択 |

- 発言 → 分類 → 図星判定で感情更新 → 許可行動を列挙 → LLM がセリフと行動を選ぶ → コードが検証して実行。
- LLM が落ちても `assets/lines/gunshi_lines.json` のテンプレートで続行。
- すべてのやりとりは `data/sessions/*.jsonl` に記録（学習用データ）。

## 行動の許可条件（session.py）
| 行動 | 誰から | 条件 | 受けた/認めた効果 |
|---|---|---|---|
| 一手待ってやろうか | 軍師 | 優勢・慢心≥0.55・相手の直前が悪手(≥150) | 相手の手と応手を戻す、慢心+0.1 |
| 置き直させて | 軍師 | 自分の直前が悪手(≥150)、1局1回 | 自分の手を戻し最善で指し直す、冷静+0.15 / 断られると焦り+0.15 |
| 取引（3手煽るな→秘密の読み筋） | 軍師 | 互角・20手以降・焦り≥0.25、1局1回 | 3手煽り禁止、「秘密」は実は3番手の手 |
| 引き分けにしないか | 軍師 | 劣勢・焦り≥0.6 | 引き分け |
| 待った | 相手 | 慢心≥0.5（またはドヤ顔）、1局3回 | 相手の手と応手を戻す |
| ヒント | 相手 | 慢心≥0.6（またはドヤ顔） | 最善手を表示 |
| 引き分け | 相手 | 劣勢、または互角で焦り≥0.5 | 引き分け |
| 投了して | 相手 | 評価値≤-2000（大混乱なら≤-1000） | 軍師が投了 |

## テスト
```
uv run pytest              # 感情・USI解析・図星・交渉フロー
uv run python tools/gen_mind_vectors.py   # 感情ロジックを変えたら共通ベクタを再生成 → flutter test でも一致確認
uv run python tools/scenario.py out.txt 7g7f "chat:その角タダじゃない？" debug:request_redo offer:accept
```

## AI同士の学習ループ（夜通し）
```
powershell -ExecutionPolicy Bypass -File tools\run_learning.ps1 -Hours 10
# 止める: data\learn\STOP という空ファイルを作る
```
- **Forge**: qwen3:8b が煽り文句を生成（速さと多様さ優先）→ gpt-oss:20b が軍師になりきって採点（図星のとき/外れのときの刺さり、逆効果、適切さ、図星/外れの返しセリフ）。遅すぎれば qwen3:8b に自動切替し、30分ごとに戻せるか試す。
- **Arena**: 煽り役AI（感情なし、初期値の強さ）vs 軍師AI（感情あり）。煽り役は「種類×図星×形勢」をUCBで選び、その種類の文句をUCB（事前値＝採点）で選ぶ。4局に1局は煽りなしの対照。
- 報酬 = 冷静さ低下 + 焦り上昇 + 直後の軍師の悪手（評価損/300、最大1.5）± 勝敗0.3。
- 出力: `data/learn/report.md`（勝率 煽りあり vs 対照、種類別効果、効いた文句）、`data/learn/candidates/`（`taunts_ranked.json`、`gunshi_lines_candidates.json`、`classifier_dataset.jsonl`）。候補は確認してからアプリの assets に反映する。
- 研究メモ: `docs/dev/taunt_research.md`
