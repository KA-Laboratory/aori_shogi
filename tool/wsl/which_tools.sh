#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
command -v uv && uv --version
ls $HOME/.local/bin 2>/dev/null
command -v litert-torch || echo "litert-torch: not yet"
