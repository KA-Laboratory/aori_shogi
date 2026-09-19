@echo off
rem Put a .litertlm on the device. Argument is a path relative to python\ .
rem   tool\dev_push_model.cmd out\litertlm17g\model.litertlm
rem Afterwards tap "install from a file on the device" on the model screen,
rem because the app keeps its own registration (see docs/dev/m3_llm_integration.md).
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
set SRC=C:\Users\amake\Claude\Projects\aori_shogi\python\%1
if not exist "%SRC%" echo NOT_FOUND %SRC% & exit /b 1
"%ADB%" -s %S% push "%SRC%" /sdcard/Android/data/%PKG%/files/gunshi.litertlm
echo PUSH_EXIT=%ERRORLEVEL%
"%ADB%" -s %S% shell ls -la /sdcard/Android/data/%PKG%/files/
