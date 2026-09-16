// 煽り将棋: やねうら王を関数呼び出しで使うための薄いC API。
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// エンジンを専用スレッドで起動する（2回目以降は何もしない）。0=成功。
int engine_init(void);

// USIコマンドを1行送る（改行なし）。
void engine_send(const char* usi_line);

// エンジン出力を1行取り出す（非ブロッキング）。
// 戻り値: 行の長さ（cap-1で切り詰め）、行がなければ -1。
int engine_poll(char* buf, int cap);

// エンジンが動いているか（quit後は0）。
int engine_is_running(void);

#ifdef __cplusplus
}
#endif
