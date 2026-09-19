#!/usr/bin/env bash
# マージ済みモデルを .litertlm にする。
#   tool\wsl_run.cmd convert     （既定: gunshi17-merged → out/litertlm17）
set -eu
export PATH="$HOME/.local/bin:$PATH"
REPO=/mnt/c/Users/amake/Claude/Projects/aori_shogi
SRC=${SRC:-$REPO/python/out/gunshi17-merged}
WORK=$HOME/gunshi-convert
OUT=${OUT:-$REPO/python/out/litertlm17}

mkdir -p "$WORK"
echo "== copy model into the WSL filesystem (/mnt/c is slow) =="
rsync -a --delete "$SRC/" "$WORK/src/" 2>/dev/null || cp -r "$SRC" "$WORK/src"
du -sh "$WORK/src"

echo "== convert =="
rm -rf "$WORK/out"
time litert-torch export_hf "$WORK/src" "$WORK/out" \
  --bundle_litert_lm \
  --quantization_recipe dynamic_wi8_emb4_afp32 \
  --externalize_embedder \
  --cache_length 1024 \
  --prefill_lengths 512 \
  --experimental_lightweight_conversion True

echo "== result =="
ls -la "$WORK/out"
mkdir -p "$OUT"
cp "$WORK/out"/*.litertlm "$OUT"/
ls -la "$OUT"
echo CONVERT_OK
