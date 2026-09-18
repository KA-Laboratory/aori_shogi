@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-0.6B --adapter out/gunshi-qwen3 --out out/gunshi-merged > out\merge.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
