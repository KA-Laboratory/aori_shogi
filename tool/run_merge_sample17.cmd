@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-1.7B --adapter out/gunshi-qwen3-1_7b --out out/gunshi17-merged > out\merge17.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17-merged --n 10 > out\sample17.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
