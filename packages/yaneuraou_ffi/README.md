# yaneuraou_ffi

煽り将棋のためのやねうら王 FFI プラグイン（GPLv3）。
`native/yaneuraou`（submodule）と `native/bridge` を `libyaneuraou` としてビルドし、
`engine_init / engine_send / engine_poll` を Dart から呼ぶ。現在 Android（arm64-v8a / x86_64）対応、iOS は未対応。
