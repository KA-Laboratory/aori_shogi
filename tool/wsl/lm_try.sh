#!/usr/bin/env bash
# 変換した .litertlm を PC 上で実際に喋らせる（量子化で日本語がどれだけ落ちるかを見る）
set -u
export PATH="$HOME/.local/bin:$PATH"
M=$HOME/gunshi-convert/out/model.litertlm
D=/mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/prompts
for f in "$D"/p*.txt; do
  echo "=== $(basename "$f") ==="
  litert-lm run "$M" --prompt "$(cat "$f")" 2>&1 | tail -12
  echo
done
