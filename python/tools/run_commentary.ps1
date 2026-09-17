# Night: generate commentary / taunt text from moments.jsonl with the LLM (GPU). Create data\learn_commentary\STOP to stop.
param([double]$Hours = 6, [string]$Model = 'gpt-oss:20b')
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\learn_commentary') | Out-Null
Remove-Item (Join-Path $root 'data\learn_commentary\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.commentary --mode generate --hours $Hours --model $Model" `
  -RedirectStandardOutput (Join-Path $root 'data\learn_commentary\stdout.log') -RedirectStandardError (Join-Path $root 'data\learn_commentary\stderr.log')
Write-Host "started: data\learn_commentary\forge.log / candidates.jsonl"
