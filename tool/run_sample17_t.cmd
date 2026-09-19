@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17-merged --n 10 --temp %1 --top_p %2 > out\sample17_t.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
