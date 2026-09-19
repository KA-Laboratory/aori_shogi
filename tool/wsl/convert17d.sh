#!/usr/bin/env bash
# 掃除したデータで学習し直した 17d を .litertlm にする。
#   tool\wsl_run.cmd convert17d
set -eu
REPO=/mnt/c/Users/amake/Claude/Projects/aori_shogi
SRC=$REPO/python/out/gunshi17d-merged OUT=$REPO/python/out/litertlm17d \
  exec bash "$REPO/tool/wsl/convert.sh"
