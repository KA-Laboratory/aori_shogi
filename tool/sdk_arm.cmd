@echo off
setlocal
set SDK=%LOCALAPPDATA%\Android\Sdk
"%SDK%\cmdline-tools\latest\bin\sdkmanager.bat" --list > "%TEMP%\sdk_list.txt" 2>&1
findstr /i arm64 "%TEMP%\sdk_list.txt"
echo ---COUNT---
findstr /i /c:"system-images" "%TEMP%\sdk_list.txt" | find /c ""
