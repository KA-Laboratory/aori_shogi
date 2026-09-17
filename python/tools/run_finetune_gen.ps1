# Start the M3 fine-tune data generation in background. Create data\finetune_gen\STOP to stop.
param([double]$Hours = 8, [string]$Model = 'gpt-oss:20b')
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\finetune_gen') | Out-Null
Remove-Item (Join-Path $root 'data\finetune_gen\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.finetune_gen --hours $Hours --model $Model" `
  -RedirectStandardOutput (Join-Path $root 'data\finetune_gen\stdout.log') -RedirectStandardError (Join-Path $root 'data\finetune_gen\stderr.log')
Write-Host "started: data\finetune_gen\stdout.log / data\finetune_gen\report.md"
