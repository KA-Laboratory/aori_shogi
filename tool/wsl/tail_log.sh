#!/usr/bin/env bash
F=${F:-$HOME/gunshi-convert/setup.log}
echo "== $F =="
tail -n 15 "$F" 2>/dev/null || echo "(no log)"
echo "== running =="
pgrep -fa "litert-torch|setup.sh|convert.sh" | head -5 || echo "(none)"
