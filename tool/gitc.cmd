@echo off
rem Windows 側で git を動かす（Cowork の Linux VM から見ると改行差で全ファイルが変更扱いになる）。
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi
git %* > %TEMP%\gitc.log 2>&1
echo GIT_EXIT=%ERRORLEVEL%
type %TEMP%\gitc.log
