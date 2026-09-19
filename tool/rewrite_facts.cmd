@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
python tools\rewrite_facts.py %1 > out\rewrite.txt 2>&1
echo EXIT=%ERRORLEVEL%
python -c "d=open('out/rewrite.txt','rb').read().decode('cp932','replace');open(r'C:\Users\amake\Claude\Projects\aori_shogi\rewrite.txt','w',encoding='utf-8').write(d)"
