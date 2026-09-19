#!/usr/bin/env bash
# 前に残った試し撃ち（長いプロンプト）だけ止める
pkill -f "model.litertlm --prompt あなたは将棋" && echo "killed old" || echo "(none)"
sleep 1
pgrep -fa "litert-lm run" | cut -c1-120
