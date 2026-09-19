@echo off
rem 実機（S24）に APK を入れ、.litertlm を push する
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
echo == install apk ==
"%ADB%" -s %S% install -r build\app\outputs\flutter-apk\app-debug.apk
echo == start once (external files dir を作らせる) ==
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 8 127.0.0.1 > nul
echo == push model (1.9GB, 数分かかる) ==
"%ADB%" -s %S% push python\out\litertlm17\model.litertlm /sdcard/Android/data/%PKG%/files/gunshi.litertlm
"%ADB%" -s %S% shell ls -l /sdcard/Android/data/%PKG%/files/
echo PUSH_DONE
