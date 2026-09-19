@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
cd /d C:\Users\amake\Claude\Projects\aori_shogi
if not "%1"=="" "%ADB%" -s %S% shell input tap %1 %2
ping -n %3 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\dev.png
echo SHOT
