@echo off
rem ŒRŽt‚Ì LoRA ŠwKBƒƒO‚Í python\out\train.log ‚ÉŽc‚·B
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if not exist out mkdir out
set HF_HUB_DISABLE_SYMLINKS_WARNING=1
.venv-train\Scripts\python.exe train\train_lora.py --base Qwen/Qwen3-0.6B --out out/gunshi-qwen3 > out\train.log 2>&1
echo TRAIN_EXIT=%ERRORLEVEL%
