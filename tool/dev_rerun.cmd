@echo off
rem APK ‚ðì‚è’¼‚µ‚ÄŽÀ‹@‚É“ü‚êAŽŽ‚µŒ‚‚¿‰æ–Ê‚Ü‚ÅŠJ‚­
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
flutter build apk --debug > build\b2.txt 2>&1
findstr /C:"Built" /C:"FAILURE" build\b2.txt
"%ADB%" -s %S% install -r build\app\outputs\flutter-apk\app-debug.apk
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 9 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 765 167
ping -n 4 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1513
ping -n 4 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 330
echo LAUNCHED
