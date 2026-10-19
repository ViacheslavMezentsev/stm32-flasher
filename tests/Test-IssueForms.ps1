$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = & python -B -X utf8 (Join-Path $repo 'ci/test_issue_forms.py') 2>&1
$output | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw 'Issue form validation failed' }
if (($output | Out-String) -match 'skipped') {
    Write-Host 'Issue forms: SKIP, PyYAML is not installed (not a PASS)'
} else {
    Write-Host 'Issue forms: syntax, unique ids/options and command coverage PASS'
}
