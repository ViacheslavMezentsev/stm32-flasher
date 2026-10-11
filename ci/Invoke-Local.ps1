param(
    [ValidateSet('All','Validate','Regression')][string]$Stage = 'All',
    [ValidateSet('Full','Quick')][string]$Profile = 'Full',
    [string[]]$TestName,
    [switch]$List,
    [string[]]$PowerShellExe = @('powershell','pwsh'),
    [string]$PythonExe = 'python',
    [string]$LogDirectory = (Join-Path $PSScriptRoot '../tests/.tmp-ci-logs')
)
$ErrorActionPreference = 'Stop'
if ($Stage -eq 'Validate' -and ($List -or $Profile -ne 'Full' -or $PSBoundParameters.ContainsKey('TestName'))) {
    throw 'Validate has no test selection; use All or Regression.'
}
$selection = @{}
if ($Profile -eq 'Quick') {
    if ($PSBoundParameters.ContainsKey('TestName')) { throw 'Use Quick or TestName, not both.' }
    $selection.TestName = @('Test-Ci.ps1','Test-ExplicitSerial.ps1','Test-Localization.ps1','Test-ProbeInventory.ps1','Test-ReleaseNotes.ps1','Test-TestRunner.ps1')
} elseif ($PSBoundParameters.ContainsKey('TestName')) { $selection.TestName = $TestName }
if ($List) {
    & (Join-Path $PSScriptRoot '../tests/Invoke-Tests.ps1') @selection -List
    return
}
# Preserve earlier attempts when the caller has not explicitly chosen a log path.
if (-not $PSBoundParameters.ContainsKey('LogDirectory')) {
    $LogDirectory = Join-Path $LogDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
if ($Stage -ne 'Regression') { & (Join-Path $PSScriptRoot 'Validate.ps1') -PythonExe $PythonExe }
if ($Stage -eq 'Validate') { return }
if (-not $PowerShellExe.Count) { throw 'At least one PowerShell executable is required.' }
# Resolve every host before starting; a missing host must not silently reduce coverage.
$hosts = @($PowerShellExe | ForEach-Object {
    (Get-Command $_ -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
})
$failed = @()
for ($i = 0; $i -lt $hosts.Count; $i++) {
    $hostPath = $hosts[$i]
    $label = '{0}-{1}' -f ($i + 1), [IO.Path]::GetFileNameWithoutExtension($hostPath)
    try {
        & (Join-Path $PSScriptRoot '../tests/Invoke-Tests.ps1') @selection -PowerShellExe $hostPath -LogDirectory (Join-Path $LogDirectory $label)
    } catch {
        $failed += $label
        Write-Warning "${label}: $_"
    }
}
if ($failed.Count) { throw "Regression failed: $($failed -join ', ')" }
