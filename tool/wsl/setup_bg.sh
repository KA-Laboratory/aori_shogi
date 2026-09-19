#!/usr/bin/env bash
# setup.sh をバックグラウンドで走らせ、ログを残す（Windows 側のツールが途中で切れても続く）
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$HOME/gunshi-convert"
nohup bash /mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/setup.sh \
  > "$HOME/gunshi-convert/setup.log" 2>&1 &
echo "started pid=$!"
