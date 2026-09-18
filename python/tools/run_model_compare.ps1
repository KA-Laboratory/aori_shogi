# Model compare: 50 rows each with gpt-oss:20b then qwen3:8b (one at a time, no GPU contention).
# Japanese comments are avoided here: PowerShell 5.1 reads BOM-less UTF-8 as ANSI and breaks the script.
$Limit = 50
$PerCall = 5
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:PYTHONIOENCODING = 'utf-8'
foreach ($m in @('gpt-oss:20b', 'qwen3:8b')) {
  $dir = 'cmp_' + ($m -replace '[:.]', '_')
  New-Item -ItemType Directory -Force (Join-Path $root "data\$dir") | Out-Null
  Remove-Item (Join-Path $root "data\$dir\STOP") -ErrorAction SilentlyContinue
  Write-Output "=== $m -> data\$dir"
  & uv run python -m aori_lab.learn.finetune_gen --hours 2 --model $m --dir $dir --limit $Limit --per-call $PerCall
}
Write-Output "=== done"
