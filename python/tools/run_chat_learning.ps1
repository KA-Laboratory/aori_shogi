# Start the free-chat / slip learning loop in background. Create data\learn_chat\STOP to stop.
param([double]$Hours = 4, [string]$Model = 'gpt-oss:20b')
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\learn_chat') | Out-Null
Remove-Item (Join-Path $root 'data\learn_chat\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.chat_arena --hours $Hours --model $Model" `
  -RedirectStandardOutput (Join-Path $root 'data\learn_chat\stdout.log') -RedirectStandardError (Join-Path $root 'data\learn_chat\stderr.log')
Write-Host "started: data\learn_chat\stdout.log / data\learn_chat\report.md"
