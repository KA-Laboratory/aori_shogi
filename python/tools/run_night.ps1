# Night: self-play + engine consensus (CPU) and LLM text generation (GPU), interleaved. Leave it running while asleep. Create data\learn_commentary\STOP to stop.
param([double]$Hours = 7, [string]$Model = 'gpt-oss:20b')
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root 'data\learn_commentary') | Out-Null
Remove-Item (Join-Path $root 'data\learn_commentary\STOP') -ErrorAction SilentlyContinue
$env:PYTHONIOENCODING = 'utf-8'
Start-Process -WindowStyle Hidden -WorkingDirectory $root -FilePath 'uv' `
  -ArgumentList "run python -m aori_lab.learn.commentary --mode both --hours $Hours --model $Model" `
  -RedirectStandardOutput (Join-Path $root 'data\learn_commentary\night_stdout.log') -RedirectStandardError (Join-Path $root 'data\learn_commentary\night_stderr.log')
Write-Host "started: data\learn_commentary\forge.log / candidates.jsonl"
