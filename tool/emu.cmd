@echo off
set SDK=%LOCALAPPDATA%\Android\Sdk
start "" "%SDK%\emulator\emulator.exe" -avd ybn_test -netdelay none -netspeed full
