# 自己対局をエミュレータで実行し、評価関数を自動で差し込む。
# 使い方: powershell -File integration_test/run_selfplay.ps1 -Device emulator-5554 -NnBin C:\path\to\nn.bin [-Composure 0.2 -Panic 0.8 -ExpectMax 0.30 -Games 50 -Movetime 100]
param(
  [string]$Device = 'emulator-5554',
  [Parameter(Mandatory=$true)][string]$NnBin,
  [string]$Composure = '0.2',
  [string]$Panic = '0.8',
  [string]$ExpectMax = '0.30',
  [int]$Games = 50,
  [int]$Movetime = 100,
  [string]$Log = 'build\selfplay.log'
)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$pkg = 'com.amkn.aori_shogi'
$job = Start-Job -ScriptBlock {
  param($adb, $Device, $NnBin, $pkg)
  for ($i = 0; $i -lt 600; $i++) {
    $installed = & $adb -s $Device shell pm list packages $pkg
    if ($installed -match $pkg) {
      Start-Sleep 3
      & $adb -s $Device shell mkdir -p /sdcard/Android/data/$pkg/files | Out-Null
      & $adb -s $Device push $NnBin /sdcard/Android/data/$pkg/files/nn.bin | Out-Null
      break
    }
    Start-Sleep 1
  }
} -ArgumentList $adb, $Device, $NnBin, $pkg
flutter test integration_test/selfplay_test.dart -d $Device `
  --dart-define=GAMES=$Games --dart-define=MOVETIME=$Movetime `
  --dart-define=COMPOSURE=$Composure --dart-define=PANIC=$Panic --dart-define=EXPECT_MAX=$ExpectMax *> $Log
Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
