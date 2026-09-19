@echo off
rem re-split all.jsonl into train/eval and rebuild the sft files
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
uv run python tools\check_edited.py data/finetune_gen_edit/all.jsonl > out\chk.txt 2>&1
echo CHECK_EXIT=%ERRORLEVEL%
uv run python tools\make_sft.py >> out\chk.txt 2>&1
echo SFT_EXIT=%ERRORLEVEL%
