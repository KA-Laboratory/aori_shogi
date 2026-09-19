@echo off
rem 実機で LLM 入りの対局を始める: 再起動 → モデル登録 → AIが後手 → ▲7六歩
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
"%ADB%" -s %S% shell am force-stop %PKG%
"%ADB%" -s %S% shell am start -n %PKG%/.MainActivity
ping -n 11 127.0.0.1 > nul
rem 「軍師の言葉」→ 端末のファイルから入れる
"%ADB%" -s %S% shell input tap 765 167
ping -n 5 127.0.0.1 > nul
"%ADB%" -s %S% shell input tap 538 1386
ping -n 30 127.0.0.1 > nul
rem 戻って対局へ
"%ADB%" -s %S% shell input keyevent 4
ping -n 4 127.0.0.1 > nul
echo READY_TO_PLAY
