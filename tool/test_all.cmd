@echo off
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi
call flutter test > C:\Users\amake\t.log 2>&1
echo TEST_EXIT=%ERRORLEVEL%
call flutter analyze >> C:\Users\amake\t.log 2>&1
echo ANALYZE_EXIT=%ERRORLEVEL%
