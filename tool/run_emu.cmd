@echo off
setlocal
set SDK=%LOCALAPPDATA%\Android\Sdk
set ADB=%SDK%\platform-tools\adb.exe
set SERIAL=%1
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %SERIAL% install -r build\app\outputs\flutter-apk\app-debug.apk
"%ADB%" -s %SERIAL% shell am force-stop %PKG%
"%ADB%" -s %SERIAL% shell am start -n %PKG%/.MainActivity
timeout /t 12 /nobreak > nul
"%ADB%" -s %SERIAL% exec-out screencap -p > build\shot.png
echo DONE
