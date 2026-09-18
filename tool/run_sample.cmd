@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi-merged --n 10 > out\sample.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
