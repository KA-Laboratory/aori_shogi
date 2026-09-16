# 自己対局（感情が手に効くかの測定）

```
powershell -ExecutionPolicy Bypass -File integration_test/run_selfplay.ps1 -NnBin C:\path\to\nn.bin
# 通常時の軍師を測る
powershell -ExecutionPolicy Bypass -File integration_test/run_selfplay.ps1 -NnBin C:\path\to\nn.bin -Composure 0.8 -Panic 0.1 -ExpectMax 1.0
```
- `flutter test` はアプリを入れ直すため、スクリプトがインストール直後に nn.bin を外部ストレージのアプリ領域へ push し、テストが取り込む。
- 結果は `build\selfplay*.log` の `SELFPLAY_REPORT` 行。

## 2026-09-16 の結果（エミュレータ x86_64 / 100ms / 50局）

| 変調側の感情 | 勝-敗 | 平均評価損 | 最善以外を選んだ率 | 悪手混入率 | 決着手数 |
|---|---|---|---|---|---|
| 崩れた c=0.2 p=0.8 | 0-50 | 150cp | 74% | 3.7% | 約40手 |
| 通常 c=0.8 p=0.1 | 0-50 | 37cp | 56% | 0% | 約85手 |

相手は変調なし（常に最善）の同エンジン。勝率はどちらも0%で飽和しているため、差は評価損と手数で見る。
