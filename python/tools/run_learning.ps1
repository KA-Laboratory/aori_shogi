# Start the learning loop in background. Create data\learn\STOP to stop.
param([double]$Hours = 8, [string]$JudgeModel = 'gpt-oss:20b', [string]$GenModel = 'gpt-oss:20b')
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\learn') | Out-Null
Remove-Item (Join-Path $root 'data\learn\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.runner --hours $Hours --judge-model $JudgeModel --gen-model $GenModel" `
  -RedirectStandardOutput (Join-Path $root 'data\learn\stdout.log') -RedirectStandardError (Join-Path $root 'data\learn\stderr.log')
Write-Host "started: data\learn\runner.log / data\learn\report.md"
