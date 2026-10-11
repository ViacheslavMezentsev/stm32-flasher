param(
    [ValidateSet('All','Validate','Regression')][string]$Stage = 'All',
    [string[]]$PowerShellExe = @('powershell','pwsh'),
    [string]$PythonExe = 'python',
    [string]$LogDirectory = (Join-Path $PSScriptRoot '../tests/.tmp-ci-logs')
)
$ErrorActionPreference = 'Stop'
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
        & (Join-Path $PSScriptRoot '../tests/Invoke-Tests.ps1') -PowerShellExe $hostPath -LogDirectory (Join-Path $LogDirectory $label)
    } catch {
        $failed += $label
        Write-Warning "${label}: $_"
    }
}
if ($failed.Count) { throw "Regression failed: $($failed -join ', ')" }
