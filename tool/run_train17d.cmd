@echo off
rem current recipe on the 528-row data with the stance words normalised
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if not exist out mkdir out
set HF_HUB_DISABLE_SYMLINKS_WARNING=1
set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
.venv-train\Scripts\python.exe train\train_lora.py --base Qwen/Qwen3-1.7B --out out/gunshi17d --batch 1 --accum 16 > out\train17d.log 2>&1
echo TRAIN_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-1.7B --adapter out/gunshi17d --out out/gunshi17d-merged --shard 350MB > out\merge17d.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17d-merged --n 12 --seed 7 --temp 0.6 --top_p 0.9 > out\sample17d.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
