$ErrorActionPreference = 'Stop'
& python -B -X utf8 (Join-Path $PSScriptRoot 'tools/test_compare.py')
if ($LASTEXITCODE -ne 0) { throw "Comparison contracts failed: $LASTEXITCODE" }
