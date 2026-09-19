@echo off
rem Windows side git (the Cowork Linux VM sees every file as modified, line endings).
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi
set LOG=%TEMP%\gitc_%RANDOM%.log
git %* > "%LOG%" 2>&1
echo GIT_EXIT=%ERRORLEVEL%
type "%LOG%"
del "%LOG%"
