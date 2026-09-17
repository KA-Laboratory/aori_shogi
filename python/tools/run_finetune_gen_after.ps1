# Wait for another learning process (by PID) to exit, then start the fine-tune data generation.
param([int]$WaitPid, [double]$Hours = 10, [string]$Model = 'gpt-oss:20b')
$p = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
if ($p) { $p.WaitForExit() }
Start-Sleep -Seconds 60
& (Join-Path $PSScriptRoot 'run_finetune_gen.ps1') -Hours $Hours -Model $Model
