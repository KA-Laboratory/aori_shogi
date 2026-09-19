@echo off
rem block-wise int4 (finer scale than wi4). Does Japanese survive at ~1GB?
setlocal
wsl -e bash /mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/convert17g_b32.sh > C:\Users\amake\Claude\Projects\aori_shogi\python\out\conv_b32.log 2>&1
echo CONV_EXIT=%ERRORLEVEL%
