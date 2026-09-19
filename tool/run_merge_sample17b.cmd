@echo off
rem 弱め LoRA を統合して、現行と同じお題・同じ seed で試し撃ちする。
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-1.7B --adapter out/gunshi17b --out out/gunshi17b-merged --shard 350MB > out\merge17b.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17b-merged --n 12 --seed 7 --temp 0.6 --top_p 0.9 > out\sample17b.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
