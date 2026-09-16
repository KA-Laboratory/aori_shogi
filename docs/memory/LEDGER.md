# LEDGER（マイルストーン記録）

- 2026-09-16 M0 完了（opus-5）: core/shogi（SFEN/USI・合法手・二歩・行き所のない駒・打ち歩詰め・千日手/連続王手・詰み・KIF）、盤UI（Riverpod、成り選択・待った・投了・KIFコピー）。perft 30/900/25470 緑、テスト15件、analyze 0件、debug APK ビルド成功。未実装: 持ち時間、入玉宣言。
- 2026-09-16 M1（Android）エミュレータ確認まで（opus-5）: packages/yaneuraou_ffi（CMake で やねうら王 + native/bridge を libyaneuraou.so、arm64/x86_64/armv7）、cin/cout 差し替えの行キューブリッジ、Dart USI クライアント（usi/isready/position/go movetime/MultiPV 収集）、NnueStore（gzip DL + SHA-256 検証）、AI対局UI（AIが後手/先手、debug のみ AI同士）。エミュレータ(x86_64, API35)で Háo 読込 → AI同士 117手で詰み終局を確認。未: Release への nn.bin.gz 配置と DL 経路の確認、実機 S24、iOS。
