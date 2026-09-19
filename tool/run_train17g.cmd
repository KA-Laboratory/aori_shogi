@echo off
rem same data as 17f, but the prompt no longer uses the word 常体 (the model
rem was parroting the grammar term into its lines)
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if not exist out mkdir out
set HF_HUB_DISABLE_SYMLINKS_WARNING=1
set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
.venv-train\Scripts\python.exe train\train_lora.py --base Qwen/Qwen3-1.7B --out out/gunshi17g --batch 1 --accum 16 > out\train17g.log 2>&1
echo TRAIN_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\merge_lora.py --base Qwen/Qwen3-1.7B --adapter out/gunshi17g --out out/gunshi17g-merged --shard 350MB > out\merge17g.log 2>&1
echo MERGE_EXIT=%ERRORLEVEL%
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17g-merged --n 12 --seed 7 --temp 0.6 --top_p 0.9 > out\sample17g.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
