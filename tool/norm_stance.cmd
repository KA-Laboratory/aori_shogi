@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
python tools\normalize_stance.py %1 > out\norm.txt 2>&1
echo EXIT=%ERRORLEVEL%
