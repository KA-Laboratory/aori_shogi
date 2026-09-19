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


## 実機で落ちた話（2026-09-19、重要）

Galaxy S24 で AI と対局すると、AI が考え始めた瞬間にアプリが落ちていた。
logcat の crash バッファに

```
Fatal signal 11 (SIGSEGV) ... in tid ... (amkn.aori_shogi)
Cause: stack pointer is not in a rw map; likely due to stack overflow.
  #135 ... libyaneuraou.so (YaneuraOu::Search::YaneuraOuWorker::search<...>)
  ...
  #139 ... (YaneuraOu::Thread::idle_loop()+276)
```

**原因**: やねうら王の探索スレッドのスタックが足りない。Android の既定スレッドスタックは 1MB で、
深い探索には足りない。やねうら王側には対策（`thread_win32_osx.h` の `NativeThread` が
pthread で 8MB のスタックを確保する）が入っているが、**`USE_PTHREADS` を定義したときだけ**有効で、
Android ビルドでは定義していなかったため `std::thread`（1MB）のままだった。

**直し方**: `packages/yaneuraou_ffi/src/CMakeLists.txt` の
`target_compile_definitions` に **`USE_PTHREADS`** を足す（1語）。実機で対局が通ることを確認済み。

エミュレータ（x86_64）では探索が浅くて済んでいたため再現しなかった。
**エンジンまわりは実機で確認しないと分からないことがある**という教訓。
