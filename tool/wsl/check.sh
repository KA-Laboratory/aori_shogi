#!/usr/bin/env bash
# WSL 側の下調べ（Windows から: tool\wsl_run.cmd check）
set -u
echo "== distro =="; head -2 /etc/os-release
echo "== cpu/mem =="; nproc; free -g | head -2
echo "== disk =="; df -h / | tail -1
echo "== tools =="
for c in uv python3 pip3 git; do printf "%-8s %s\n" "$c" "$(command -v $c || echo '-')"; done
echo "== repo =="; ls /mnt/c/Users/amake/Claude/Projects/aori_shogi/python/out 2>/dev/null | head
