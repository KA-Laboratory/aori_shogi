#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
litert-lm run --help 2>&1 | head -30
echo "== procs =="
pgrep -fa litert-lm | head -3 || echo none
