@echo off
rem regenerate worksheet.txt from the existing skeleton.jsonl (no new skeleton)
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
uv run python tools\make_worksheet.py > out\sheet.txt 2>&1
echo SHEET_EXIT=%ERRORLEVEL%
