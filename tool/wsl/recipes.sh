#!/usr/bin/env bash
# litert-torch が受け付ける量子化レシピ名を探す（.litertlm を小さくできるか調べるため）。
set -eu
SITE=$(ls -d "$HOME"/.local/share/uv/tools/litert-torch-nightly/lib/python*/site-packages/litert_torch 2>/dev/null | head -1)
echo "SITE=$SITE"
grep -rhoE "dynamic_[a-z0-9_]+" "$SITE" 2>/dev/null | sort -u
echo "--- recipe modules ---"
find "$SITE" -iname '*recipe*' -o -iname '*quant*' 2>/dev/null | head -20
