#!/usr/bin/env bash
# 17g を int4 重みで変換して、どれだけ小さくなるか見る（配布 1.90GB を減らせるか）。
#   tool\wsl_run.cmd convert17g_i4
set -eu
export PATH="$HOME/.local/bin:$PATH"
REPO=/mnt/c/Users/amake/Claude/Projects/aori_shogi
SRC=$REPO/python/out/gunshi17g-merged
WORK=$HOME/gunshi-convert
OUT=$REPO/python/out/litertlm17g_i4
RECIPE=${RECIPE:-dynamic_wi4_afp32}

mkdir -p "$WORK"
rsync -a --delete "$SRC/" "$WORK/src/" 2>/dev/null || cp -r "$SRC" "$WORK/src"

echo "== convert with $RECIPE =="
rm -rf "$WORK/out_i4"
time litert-torch export_hf "$WORK/src" "$WORK/out_i4" \
  --bundle_litert_lm \
  --quantization_recipe "$RECIPE" \
  --externalize_embedder \
  --cache_length 1024 \
  --prefill_lengths 512 \
  --experimental_lightweight_conversion True

ls -la "$WORK/out_i4"
mkdir -p "$OUT"
cp "$WORK/out_i4"/*.litertlm "$OUT"/
ls -la "$OUT"
echo CONVERT_OK
