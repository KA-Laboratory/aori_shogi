@echo off
rem merge the cleaned-data model and sample it on the same prompts / seed as 17a
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-1.7B --adapter out/gunshi17c --out out/gunshi17c-merged --shard 350MB > out\merge17c.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17c-merged --n 12 --seed 7 --temp 0.6 --top_p 0.9 > out\sample17c.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
