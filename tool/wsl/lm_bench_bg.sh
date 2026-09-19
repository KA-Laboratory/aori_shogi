#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
setsid nohup bash /mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/lm_bench.sh > /dev/null 2>&1 < /dev/null &
echo "started $!"
sleep 2
pgrep -fa litert-lm | head -2 || echo "(not yet)"
