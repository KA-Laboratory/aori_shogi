#!/usr/bin/env bash
# 17g をチャンネルごとのスケールの int4 で変換する。
# per-tensor の wi4 は日本語が壊れたが、粒度が細かい wi4c なら持つかもしれない。
#   tool\conv_b32.cmd
#
# 注意: dynamic_int4_block32 / block128 は export_hf では使えない
# （KeyError になる。パッケージ内の別の場所の名前だった）。
# export_hf が受け付けるのは dynamic_w{i8,i8c,i4,i4c}_afp32 と dynamic_wi8_emb4_afp32。
set -eu
export PATH="$HOME/.local/bin:$PATH"
REPO=/mnt/c/Users/amake/Claude/Projects/aori_shogi
SRC=$REPO/python/out/gunshi17g-merged
WORK=$HOME/gunshi-convert
OUT=$REPO/python/out/litertlm17g_wi4c

mkdir -p "$WORK"
rsync -a --delete "$SRC/" "$WORK/src/" 2>/dev/null || cp -r "$SRC" "$WORK/src"

echo "== convert with dynamic_wi4c_afp32 =="
rm -rf "$WORK/out_wi4c"
time litert-torch export_hf "$WORK/src" "$WORK/out_wi4c" \
  --bundle_litert_lm \
  --quantization_recipe dynamic_wi4c_afp32 \
  --externalize_embedder \
  --cache_length 1024 \
  --prefill_lengths 512 \
  --experimental_lightweight_conversion True

ls -la "$WORK/out_wi4c"
mkdir -p "$OUT"
cp "$WORK/out_wi4c"/*.litertlm "$OUT"/
ls -la "$OUT"
echo CONVERT_OK
