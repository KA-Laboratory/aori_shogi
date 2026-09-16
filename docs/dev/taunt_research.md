# 煽りの研究メモ（学習ループの生成プロンプトの根拠）

2026-09-16 調査。生成器には下記を「型」として一般化して渡す（`python/aori_lab/learn/research.py`）。

## 分かったこと
- **盤外戦**（将棋・囲碁）の類型: 時間の使い方、ぼやき・独り言、態度や所作、対局前の心理的圧力、敗者への言葉など。現代では避けるべきとされ、ネット中継の普及で減っている。→ アプリでは「軍師というキャラ相手の遊び」に限定し、実在の人への応用を想定しない。
- **Trash-talking の研究**（競争的無礼）: 煽られた側は競争課題ではむしろ努力が増え成績が上がり、相手を負かしたい動機が強まる。創造性を要する課題では成績を下げる。→ 露骨な侮辱は「逆効果（奮起）」、盤面の事実を突く具体的な指摘（読み＝創造的課題を乱す）が効く、という設計にする。採点に backfire（逆効果）を入れた根拠。
- 解説でよく使う将棋用語（筋が悪い、形、利かし、受けなし、敗着 など）は短く具体的で刺さりやすい語彙として生成器に促す。

## 学習ループへの反映
| 研究の示唆 | 実装 |
|---|---|
| 事実に当たる指摘ほど効く | 図星判定（エンジン）× 採点 sting_if_true / sting_if_false |
| 侮辱は奮起させ逆効果 | 採点 backfire ≥ 6 で冷静さが戻る |
| 慣れると効かない | 耐性 resistance（同種連発で上昇） |
| 不適切表現は出さない | 採点 appropriate=false は使用禁止 |

## 出典
- 盤外戦 - Wikipedia https://ja.wikipedia.org/wiki/盤外戦
- Yip, Schweitzer, Nurmohamed (2018) "Trash-talking: Competitive incivility motivates rivalry, performance, and unethical behavior" https://core.ac.uk/works/19102002
- 将棋用語一覧 - Wikipedia https://ja.wikipedia.org/wiki/将棋用語一覧
