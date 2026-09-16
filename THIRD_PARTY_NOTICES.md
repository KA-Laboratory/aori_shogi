# 第三者ソフトウェア

本アプリは GNU General Public License v3（LICENSE）で公開します。以下を含みます。

| 名称 | 用途 | ライセンス | 入手元 |
|---|---|---|---|
| やねうら王 (YaneuraOu) | 思考エンジン（`native/yaneuraou`, submodule） | GPLv3 | https://github.com/yaneurao/YaneuraOu |
| Háo（tanuki- 標準NNUE評価関数 halfkp_256x2-32-32, 2023-05-08） | 評価関数 `nn.bin`（初回起動時にダウンロード。アプリには同梱しない） | GPLv3 | https://github.com/nodchip/tanuki-/releases/tag/tanuki-.halfkp_256x2-32-32.2023-05-08 |

評価関数の配布: `KA-Laboratory/aori_shogi` の Release `nnue-hao-2023-05-08` に、元ファイルを gzip 圧縮した
`nn.bin.gz` と `gpl-3.0.txt` を置く。展開後 64,217,066 バイト、SHA-256
`1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782`（アプリが検証）。
