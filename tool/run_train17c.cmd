@echo off
rem current recipe (rank16 / lr1e-4 / 4ep) on the cleaned 528-row data
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if not exist out mkdir out
set HF_HUB_DISABLE_SYMLINKS_WARNING=1
set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
.venv-train\Scripts\python.exe train\train_lora.py --base Qwen/Qwen3-1.7B --out out/gunshi17c --batch 1 --accum 16 > out\train17c.log 2>&1
echo TRAIN_EXIT=%ERRORLEVEL%
