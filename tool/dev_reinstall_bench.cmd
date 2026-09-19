@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
"%ADB%" -s %S% shell input keyevent 4
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1386
ping -n 30 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1513
ping -n 5 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 330
echo RERUN_STARTED
