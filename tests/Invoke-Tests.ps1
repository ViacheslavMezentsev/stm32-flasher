param(
    [string]$PowerShellExe = (Get-Process -Id $PID).Path,
    [string]$LogDirectory = (Join-Path $PSScriptRoot '.tmp-ci-logs')
)
$ErrorActionPreference = 'Stop'
$PowerShellExe = (Get-Command $PowerShellExe -CommandType Application -ErrorAction Stop).Source
$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' -File | Sort-Object Name)
if (-not $tests.Count) { throw 'No regression tests found.' }
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$results = @()
foreach ($test in $tests) {
    Write-Host "Running $($test.Name) with $PowerShellExe"
    $log = Join-Path $LogDirectory ($test.BaseName + '.log')
    # Isolate each suite, including scripts that call exit. Native stderr is
    # captured as diagnostic output; the process exit code determines success.
    $ErrorActionPreference = 'Continue'
    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $test.FullName > $log 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
    $results += [pscustomobject]@{ Test = $test.Name; ExitCode = $code; Passed = ($code -eq 0) }
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LogDirectory 'results.json') -Encoding UTF8
$results | Format-Table -AutoSize | Out-Host
if (@($results | Where-Object { -not $_.Passed }).Count) { throw 'Regression tests failed. See logs and results.json.' }
Write-Host "All $($tests.Count) test suites passed."
