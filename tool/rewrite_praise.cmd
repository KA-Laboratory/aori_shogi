@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
python tools\rewrite_praise.py %1 > out\praise.txt 2>&1
echo EXIT=%ERRORLEVEL%
python -c "d=open('out/praise.txt','rb').read().decode('cp932','replace');open(r'C:\Users\amake\Claude\Projects\aori_shogi\praise.txt','w',encoding='utf-8').write(d)"
