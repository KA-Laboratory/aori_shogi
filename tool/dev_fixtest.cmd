@echo off
rem ’¼‚µ‚½ƒGƒ“ƒWƒ“‚ÅALLM –³‚µ‚Ì‘Î‹Ç‚ðŽŽ‚·
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% install -r build\app\outputs\flutter-apk\app-debug.apk
"%ADB%" -s %S% shell run-as %PKG% mkdir -p files/eval
"%ADB%" -s %S% shell run-as %PKG% cp /data/local/tmp/nn.bin files/eval/nn.bin
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 12 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 326 2120
ping -n 6 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1651
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1509
ping -n 18 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\dev.png
echo FIXED_TEST_DONE
