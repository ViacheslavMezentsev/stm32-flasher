$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
& python -B -X utf8 (Join-Path $repo 'ci/test_site.py')
if ($LASTEXITCODE -ne 0) { throw 'Pages validation failed' }
Write-Host 'Pages: bilingual command coverage, links, assets and deterministic build PASS'
