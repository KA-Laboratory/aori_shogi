# Day: self-play and multi-engine analysis (CPU) -> moments.jsonl. Create data\learn_commentary\STOP to stop.
param([double]$Hours = 2)
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\learn_commentary') | Out-Null
Remove-Item (Join-Path $root 'data\learn_commentary\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.commentary --mode extract --hours $Hours" `
  -RedirectStandardOutput (Join-Path $root 'data\learn_commentary\extract_stdout.log') -RedirectStandardError (Join-Path $root 'data\learn_commentary\extract_stderr.log')
Write-Host "started: data\learn_commentary\forge.log / moments.jsonl"
