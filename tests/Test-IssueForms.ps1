$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
# stdout only: PS 5.1 with Stop treats redirected stderr lines as terminating errors.
$output = @(& python -B -X utf8 (Join-Path $repo 'ci/test_issue_forms.py'))
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }
if ($code -ne 0) { throw "Issue form validation failed: $code" }
if ($output -contains 'ISSUE_FORMS_SKIPPED: PyYAML is not installed') {
    Write-Host 'Issue forms: SKIP, PyYAML is not installed (not a PASS)'
} else {
    Write-Host 'Issue forms: syntax, unique ids/options and command coverage PASS'
}
