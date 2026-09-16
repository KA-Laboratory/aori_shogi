# 開発時の評価関数（nn.bin）配置

リポジトリ非公開の間はアプリ内ダウンロードが使えないため、debug ビルドに adb で置く。

1. Háo を取得・展開: https://github.com/nodchip/tanuki-/releases/tag/tanuki-.halfkp_256x2-32-32.2023-05-08 （`eval/nn.bin`）
   または `git fetch origin nnue-assets` の `nn.bin.gz` を展開
2. 配置（debug ビルドのみ run-as が使える）
   ```
   adb push nn.bin /data/local/tmp/nn.bin
   adb shell "run-as com.amkn.aori_shogi mkdir -p files/eval && run-as com.amkn.aori_shogi cp /data/local/tmp/nn.bin files/eval/nn.bin"
   ```
3. アプリのエンジン欄で「再確認」（または再起動）

サイズ 64,217,066 バイトで「インストール済み」と判定する。
