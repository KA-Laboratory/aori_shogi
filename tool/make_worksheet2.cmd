@echo off
rem second round of hand-written lines: weighted to the scenes that looked weakest
rem in the S24 bench (move mis-reads the score; praise / dodge / endgame are thin)
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
if exist data\finetune_gen_edit\worksheet.txt move /y data\finetune_gen_edit\worksheet.txt data\finetune_gen_edit\worksheet_1.txt > nul
if exist data\finetune_gen_edit\skeleton.jsonl move /y data\finetune_gen_edit\skeleton.jsonl data\finetune_gen_edit\skeleton_1.jsonl > nul
uv run python tools\build_skeleton.py --want move=100,taunt_hit=50,taunt_miss=50,praised=40,praise_suspicious=28,question_dodge=33,blunder_self=32,blunder_opponent=31,checkmate_threat=27,win=12,lose=12,draw=8 > out\skel2.txt 2>&1
echo SKEL_EXIT=%ERRORLEVEL%
uv run python tools\make_worksheet.py >> out\skel2.txt 2>&1
echo SHEET_EXIT=%ERRORLEVEL%
