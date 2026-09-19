@echo off
rem Is the app still running, and what is on screen?
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
"%ADB%" -s %S% shell pidof com.amkn.aori_shogi
echo PIDOF_EXIT=%ERRORLEVEL%
"%ADB%" -s %S% shell dumpsys activity activities > %TEMP%\act.txt 2>&1
findstr /c:"mResumedActivity" %TEMP%\act.txt
