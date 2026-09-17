# 煽りスタンプの追加案（2026-09-18, opus-5）

解説学習（gpt-oss:20b, Apache 2.0）が出した1290件を `python/tools/triage_commentary.py` でふるい、さらに読んで選んだもの。採用は賢太郎さんの判断で。

## 正直なところ

生成された煽りの多くは**そのままスタンプには使えない**。理由は2つ。

1. 「この歩、まるで無駄打ちだ」のように、その局面の駒を指しているものが大半。スタンプはどの局面でも押せる言葉でないといけない。
2. 日本語がぎこちないものが多い（「この手、まるで鏡の前の石のように無意味だ」）。

なので**自動で入れるのはやめ**、生成物は次の2つの使い道に限るのがよいと思う。

- **自由入力の分類器の学習データ**（`data/learn_commentary/classifier_commentary.jsonl`、種類つきで1290件）。辞書 `tool/shogi_terms.src.json` の追加語を拾うのにも使える。
- **局面依存の煽り**（将来、プレイヤー側に「この駒が浮いている」と指摘させる補助を出すとき）。

## スタンプ案（15件、文は読みやすさのため手直し済み）

今は種類ごとに1つ（計5つ）なので、3つずつに増やす案。押し間違いを防ぐため、種類ごとにまとめて表示する。

```dart
const tauntStamps = <TauntStamp>[
  // 悪手の指摘
  TauntStamp('blunder1', TauntKind.blunderCall, 'いまの手、悪手でしょ'),
  TauntStamp('blunder2', TauntKind.blunderCall, 'いまの一手、意味あった？'),
  TauntStamp('blunder3', TauntKind.blunderCall, 'それ、何を考えて指したの？'),
  // 駒が浮いている
  TauntStamp('hanging1', TauntKind.hangingPiece, '駒、浮いてない？'),
  TauntStamp('hanging2', TauntKind.hangingPiece, 'その駒、取られたらどうするの？'),
  TauntStamp('hanging3', TauntKind.hangingPiece, 'そこ、タダで取れそうだけど'),
  // 詰みの脅し
  TauntStamp('threat1', TauntKind.threat, '玉、危なくない？'),
  TauntStamp('threat2', TauntKind.threat, 'そろそろ王手が来るよ'),
  TauntStamp('threat3', TauntKind.threat, '玉の逃げ道、もう無いよね'),
  // 自称天才をからかう
  TauntStamp('mock1', TauntKind.mock, '天才軍師（笑）'),
  TauntStamp('mock2', TauntKind.mock, 'こんな手で天下を取るつもり？'),
  TauntStamp('mock3', TauntKind.mock, 'その読み、どこへ行ったの？'),
  // 褒めて慢心させる
  TauntStamp('praise1', TauntKind.praise, 'さすが天才軍師さま！'),
  TauntStamp('praise2', TauntKind.praise, 'いまの一手で勝負が決まったね'),
  TauntStamp('praise3', TauntKind.praise, '君の戦術、やっぱり面白いよ'),
];
```

元の候補一覧は `python/data/learn_commentary/review/taunt_stamps.md`（種類別・重複なしで938件）。

## 判断してほしいこと

- この15件でよいか（文の直しも遠慮なく）。
- スタンプを3つずつに増やすと画面が狭くなる。種類を選んでから文を選ぶ2段にするか、横スクロールにするか。
