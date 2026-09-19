@echo off
rem 現行（rank 16 / lr 1e-4 / 4 epoch）を 17b と同じお題・同じ seed で試し撃ちする。
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe train\sample.py --model out/gunshi17-merged --n 12 --seed 7 --temp 0.6 --top_p 0.9 > out\sample17a.log 2>&1
echo SAMPLE_EXIT=%ERRORLEVEL%
