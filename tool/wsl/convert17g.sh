#!/usr/bin/env bash
# 事実をアプリの型に揃え、プロンプトから「常体」を外して学習した 17g を .litertlm にする。
#   tool\wsl_run.cmd convert17g
set -eu
REPO=/mnt/c/Users/amake/Claude/Projects/aori_shogi
SRC=$REPO/python/out/gunshi17g-merged OUT=$REPO/python/out/litertlm17g \
  exec bash "$REPO/tool/wsl/convert.sh"
