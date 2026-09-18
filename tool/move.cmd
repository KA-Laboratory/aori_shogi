@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=emulator-5554
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% shell input tap 314 1525
ping -n 2 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 314 1404
ping -n 12 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\shot.png
echo MOVED
