@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% logcat -d -b crash -t 200 > build\crash.txt 2>&1
"%ADB%" -s %S% shell dumpsys activity processes | findstr /i aori > build\proc.txt 2>&1
echo --- crash ---
type build\crash.txt
echo --- proc ---
type build\proc.txt
echo LOG2_DONE
