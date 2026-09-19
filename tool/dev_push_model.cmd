@echo off
rem .litertlm を実機に置く。引数は python\ からの相対パス。
rem   tool\dev_push_model.cmd out\litertlm17d\model.litertlm
rem 置いたあと、アプリの「モデル」画面で「端末に置いたファイルから入れる」を押す。
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
set SRC=C:\Users\amake\Claude\Projects\aori_shogi\python\%1
if not exist "%SRC%" echo NOT_FOUND %SRC% & exit /b 1
"%ADB%" -s %S% push "%SRC%" /sdcard/Android/data/%PKG%/files/gunshi.litertlm
echo PUSH_EXIT=%ERRORLEVEL%
"%ADB%" -s %S% shell ls -la /sdcard/Android/data/%PKG%/files/
