$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-ci-entry-' + [guid]::NewGuid().ToString('N'))
$hostExe = (Get-Process -Id $PID).Path
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Run-Ci([string[]]$extra) {
    $entry = Join-Path $root 'ci/Invoke-Local.ps1'
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $entry @extra 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
    } finally { $ErrorActionPreference = $oldPreference }
}
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'ci'), (Join-Path $root 'tests') | Out-Null
    Copy-Item (Join-Path $repo 'ci/Invoke-Local.ps1') (Join-Path $root 'ci')
    Copy-Item (Join-Path $repo 'tests/Invoke-Tests.ps1') (Join-Path $root 'tests')
    Set-Content (Join-Path $root 'ci/Validate.ps1') "param([string]`$PythonExe); Write-Output 'VALIDATED'" -Encoding ASCII
    Set-Content (Join-Path $root 'tests/Test-01.ps1') "Write-Output 'SUITE_OK'" -Encoding ASCII
    $logs = Join-Path $root 'logs'
    $result = Run-Ci @('-Stage','Validate')
    Assert ($result.Code -eq 0 -and $result.Output -match 'VALIDATED' -and $result.Output -notmatch 'SUITE_OK') 'Validate stage ran regressions or failed'
    $result = Run-Ci @('-PowerShellExe',$hostExe,'-LogDirectory',$logs)
    Assert ($result.Code -eq 0 -and $result.Output -match 'VALIDATED' -and $result.Output -match 'SUITE_OK') 'All stages did not run'
    Assert (@(Get-ChildItem $logs -Filter results.json -Recurse).Count -eq 1) 'Missing per-host results'
    Set-Content (Join-Path $root 'ci/Validate.ps1') "throw 'VALIDATION_FAILED'" -Encoding ASCII
    $result = Run-Ci @('-PowerShellExe',$hostExe,'-LogDirectory',$logs)
    Assert ($result.Code -ne 0 -and $result.Output -notmatch 'SUITE_OK') 'Validation failure did not stop All'
    $result = Run-Ci @('-Stage','Regression','-PowerShellExe',$hostExe,'-LogDirectory',$logs)
    Assert ($result.Code -eq 0 -and $result.Output -notmatch 'VALIDATION_FAILED') 'Regression unexpectedly required validation'
    Set-Content (Join-Path $root 'tests/Test-01.ps1') 'exit 7' -Encoding ASCII
    Set-Content (Join-Path $root 'tests/Test-02.ps1') "Write-Output 'AFTER_FAILURE'" -Encoding ASCII
    $result = Run-Ci @('-Stage','Regression','-PowerShellExe',$hostExe,'-LogDirectory',$logs)
    Assert ($result.Code -ne 0 -and $result.Output -match 'AFTER_FAILURE') 'Suite failure was masked or stopped subsequent suites'
    $result = Run-Ci @('-Stage','Regression','-PowerShellExe','missing-ci-host-12345')
    Assert ($result.Code -ne 0) 'Missing shell was silently skipped'
    # Calling in-process supports an array and verifies fail-fast:false between hosts.
    $multiLogs = Join-Path $root 'multi'
    $failed = $false
    Write-Host 'Expected failures below verify that both hosts run and return failure.'
    try { & (Join-Path $root 'ci/Invoke-Local.ps1') -Stage Regression -PowerShellExe @($hostExe,$hostExe) -LogDirectory $multiLogs } catch { $failed = $true }
    Assert $failed 'Multiple-host failures were masked'
    Assert (@(Get-ChildItem $multiLogs -Filter results.json -Recurse).Count -eq 2) 'Failure prevented the second host from running'
    $pythonStub = Join-Path $root 'python-stub.cmd'
    Set-Content $pythonStub "@echo off`r`nexit /b 7" -Encoding ASCII
    $preference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'ci/Validate.ps1') -PythonExe $pythonStub 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $preference }
    Assert ($code -ne 0 -and $output -match 'Specification check failed: 7') 'Specification checker failure was masked'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if ((Split-Path -Parent $resolved) -ne $PSScriptRoot) { throw 'Invalid fixture root' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host 'CI stages, logs, missing dependencies and failure propagation PASS'
