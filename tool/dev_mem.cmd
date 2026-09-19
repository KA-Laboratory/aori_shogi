@echo off
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
"%ADB%" -s %S% shell dumpsys meminfo com.amkn.aori_shogi | findstr /C:"TOTAL PSS" /C:"TOTAL RSS" /C:"Native Heap"
