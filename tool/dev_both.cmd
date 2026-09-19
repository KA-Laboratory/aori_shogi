@echo off
rem ƒGƒ“ƒWƒ“{LLM ‚ð“¯Žž‚ÉŽg‚¤–{”Ô‚Ì—¬‚ê: ƒ‚ƒfƒ‹“o˜^ ¨ AI ‚ªŒãŽè ¨ £7˜Z•à
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 12 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 765 167
ping -n 5 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1386
ping -n 30 127.0.0.1 > nul
"%ADB%" -s %S% shell input keyevent 4
ping -n 4 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 326 2120
ping -n 6 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1651
ping -n 3 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 309 1509
ping -n 20 127.0.0.1 > nul
"%ADB%" -s %S% exec-out screencap -p > build\dev.png
echo BOTH_DONE
