@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %1 shell input tap %2 %3
ping -n 4 127.0.0.1 > nul
"%ADB%" -s %1 exec-out screencap -p > build\shot.png
echo TAPPED
