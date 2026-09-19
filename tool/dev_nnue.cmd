@echo off
rem 実機に NNUE 評価関数を置く（debug ビルドのみ run-as が使える）
setlocal
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set S=R5CY545133H
set PKG=com.amkn.aori_shogi
cd /d C:\Users\amake\Claude\Projects\aori_shogi
"%ADB%" -s %S% push python\engine\eval\nn.bin /data/local/tmp/nn.bin
"%ADB%" -s %S% shell run-as %PKG% mkdir -p files/eval
"%ADB%" -s %S% shell run-as %PKG% cp /data/local/tmp/nn.bin files/eval/nn.bin
"%ADB%" -s %S% shell run-as %PKG% ls -l files/eval
echo NNUE_DONE
