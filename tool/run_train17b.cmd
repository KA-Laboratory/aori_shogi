@echo off
rem 弱めの LoRA（rank 8 / lr 5e-5 / 3 epoch）。
rem 現行（rank 16 / lr 1e-4 / 4 epoch）は口調は付くが「ございる」のような
rem 崩れた活用を作る。土台の日本語を壊さない強さを探すための比較用。
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if not exist out mkdir out
set HF_HUB_DISABLE_SYMLINKS_WARNING=1
set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
.venv-train\Scripts\python.exe train\train_lora.py --base Qwen/Qwen3-1.7B --out out/gunshi17b --rank 8 --alpha 16 --lr 5e-5 --epochs 3 --batch 1 --accum 16 > out\train17b.log 2>&1
echo TRAIN_EXIT=%ERRORLEVEL%
