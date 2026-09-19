#!/usr/bin/env bash
# 変換ツールを WSL に入れる（1回だけ）
set -eu
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv > /dev/null; then
  echo "== install uv =="
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
echo "== uv =="; uv --version
echo "== litert-torch-nightly =="
uv tool install litert-torch-nightly
echo "== litert-lm （PC で .litertlm を試し撃ちする用） =="
uv tool install litert-lm || echo "litert-lm は入らなかった（変換だけなら要らない）"
echo SETUP_OK
