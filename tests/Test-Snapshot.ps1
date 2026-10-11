$ErrorActionPreference = 'Stop'
$hostExe = (Get-Process -Id $PID).Path
& python -B -X utf8 (Join-Path $PSScriptRoot 'tools/test_snapshot.py') --powershell $hostExe
if ($LASTEXITCODE -ne 0) { throw "Snapshot/benchmark contracts failed: $LASTEXITCODE" }
