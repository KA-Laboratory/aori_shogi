@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=emulator-5554
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% shell input keyevent 4
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 294 1952
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 314 1168
ping -n 2 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 314 1056
ping -n 9 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\shot.png
echo PLAYED
