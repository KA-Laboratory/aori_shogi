@echo off
setlocal
wsl -e bash /mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/convert17d.sh > C:\Users\amake\Claude\Projects\aori_shogi\python\out\conv17d.log 2>&1
echo CONV_EXIT=%ERRORLEVEL%
