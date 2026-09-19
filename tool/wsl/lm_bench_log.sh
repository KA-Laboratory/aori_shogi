#!/usr/bin/env bash
cat $HOME/gunshi-convert/lm_bench.log 2>/dev/null | tail -30 || echo "(no log)"
echo "== running =="
pgrep -fa "litert-lm run" | head -2 || echo none
