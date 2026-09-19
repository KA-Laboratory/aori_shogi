#!/usr/bin/env bash
# 変換した .litertlm を PC 上で喋らせる。ログはファイルに残す（WSL は CPU なので遅い）。
export PATH="$HOME/.local/bin:$PATH"
M=$HOME/gunshi-convert/out/model.litertlm
LOG=$HOME/gunshi-convert/lm_bench.log
: > "$LOG"
{
  echo "=== short ==="
  date +%T
  timeout 600 litert-lm run "$M" --prompt "こんにちは。あなたは誰ですか。" 2>&1
  date +%T
} >> "$LOG" 2>&1
echo "wrote $LOG"
