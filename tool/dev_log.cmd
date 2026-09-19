@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% logcat -d -t 400 > build\logcat.txt 2>&1
findstr /i /c:"aori" /c:"lowmemorykiller" /c:"ActivityManager" /c:"FATAL" /c:"died" build\logcat.txt | findstr /v /c:"Background concurrent" > build\logcat_f.txt
type build\logcat_f.txt
echo LOG_DONE
