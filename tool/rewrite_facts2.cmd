@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
python tools\rewrite_facts2.py %1 > out\rw2.txt 2>&1
echo EXIT=%ERRORLEVEL%
python -c "d=open('out/rw2.txt','rb').read().decode('cp932','replace');open(r'C:\Users\amake\Claude\Projects\aori_shogi\rw2.txt','w',encoding='utf-8').write(d)"
