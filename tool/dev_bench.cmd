@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 10 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 765 167
ping -n 5 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1513
ping -n 5 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 330
echo BENCH_STARTED
