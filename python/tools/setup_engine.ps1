# やねうら王 V9.00（win64, NNUE halfkp_256x2-32-32, AVX2）と評価関数 Háo を python/engine に配置する。
# どちらも GPLv3。出典は THIRD_PARTY_NOTICES.md。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'engine'
New-Item -ItemType Directory -Force (Join-Path $engine 'eval') | Out-Null
$tmp = Join-Path $env:TEMP 'aori_engine_setup'
New-Item -ItemType Directory -Force $tmp | Out-Null
Push-Location $tmp
if (-not (Test-Path yo.7z)) {
  Invoke-WebRequest https://github.com/yaneurao/YaneuraOu/releases/download/V9.00/yaneuraou-V900-git-win64-all.7z -OutFile yo.7z
}
tar -xf yo.7z
Copy-Item 'NNUE_halfkp_256x2_32_32\YaneuraOu_NNUE_halfkp_256x2_32_32-V900Git_AVX2.exe' $engine -Force
if (-not (Test-Path hao.7z)) {
  Invoke-WebRequest https://github.com/nodchip/tanuki-/releases/download/tanuki-.halfkp_256x2-32-32.2023-05-08/tanuki-.halfkp_256x2-32-32.2023-05-08.7z -OutFile hao.7z
}
tar -xf hao.7z
Copy-Item 'eval\nn.bin' (Join-Path $engine 'eval\nn.bin') -Force
Copy-Item 'gpl-3.0.txt' (Join-Path $engine 'gpl-3.0.txt') -Force
Pop-Location
$hash = (Get-FileHash (Join-Path $engine 'eval\nn.bin')).Hash.ToLower()
if ($hash -ne '1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782') { throw "nn.bin hash mismatch: $hash" }
Write-Host "OK: $engine"
