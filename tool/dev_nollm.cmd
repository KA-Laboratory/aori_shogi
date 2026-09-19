@echo off
rem LLM 無しで同じ手を指して、落ちるかどうかを見る（原因の切り分け）
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% shell pm clear %PKG%
"%ADB%" -s %S% shell run-as %PKG% mkdir -p files/eval
"%ADB%" -s %S% shell run-as %PKG% cp /data/local/tmp/nn.bin files/eval/nn.bin
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 12 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 326 2120
ping -n 6 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1651
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1509
ping -n 16 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\dev.png
echo NOLLM_DONE
