# nnue-assets

煽り将棋（aori_shogi）がアプリ初回起動時にダウンロードする評価関数ファイル置き場。main の履歴とは独立したブランチ。

- nn.bin.gz: Háo（tanuki- 標準NNUE評価関数 halfkp_256x2-32-32, 2023-05-08）を gzip 圧縮したもの
  - 出典: https://github.com/nodchip/tanuki-/releases/tag/tanuki-.halfkp_256x2-32-32.2023-05-08
  - ライセンス: GPLv3（gpl-3.0.txt、配布元アーカイブに同梱のもの）
  - 展開後 64,217,066 バイト / SHA-256 1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782
  - 推奨 FV_SCALE=20
