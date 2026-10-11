param(
    [Parameter(Mandatory=$true)][string]$SnapshotDirectory,
    [ValidateSet(1,2)][int]$Workers = 1,
    [string[]]$PowerShellExe = @('powershell','pwsh'),
    [string]$PythonExe = 'python',
    [string[]]$TestName,
    [switch]$List,
    [ValidateRange(1,86400)][int]$SuiteTimeoutSeconds = 600,
    [ValidateRange(1,86400)][int]$RunTimeoutSeconds = 1800,
    [string]$LogDirectory
)
$ErrorActionPreference = 'Stop'
$snapshot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotDirectory)
$python = (Get-Command $PythonExe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
# Verify with the caller's trusted helper before executing the captured runner.
& $python -B -X utf8 (Join-Path $PSScriptRoot 'snapshot.py') verify --destination $snapshot
if ($LASTEXITCODE -ne 0) { throw 'Invalid snapshot; no tests started.' }
$runner = Join-Path $snapshot 'source/ci/isolated.py'
$arguments = @('-B','-X','utf8',$runner,'--snapshot',$snapshot,'--workers',"$Workers")
if ($PSBoundParameters.ContainsKey('TestName')) {
    if (-not $TestName.Count) { throw 'TestName cannot be empty.' }
    foreach ($name in $TestName) { $arguments += @('--suite',$name) }
}
if ($List) {
    & $python @arguments --list
    if ($LASTEXITCODE -ne 0) { throw 'Invalid test selection.' }
    return
}
if (-not $PowerShellExe.Count) { throw 'At least one PowerShell executable is required.' }
$hosts = @($PowerShellExe | ForEach-Object { (Get-Command $_ -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source })
if (-not $LogDirectory) {
    $LogDirectory = Join-Path $PSScriptRoot ('../tests/.tmp-ci-isolated/' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$logs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogDirectory)
if (Test-Path -LiteralPath $logs) { throw 'Use a fresh LogDirectory; previous evidence is never overwritten.' }
$failed = @()
for ($i=0; $i -lt $hosts.Count; $i++) {
    $label = '{0}-{1}' -f ($i+1), [IO.Path]::GetFileNameWithoutExtension($hosts[$i])
    & $python @arguments --host $hosts[$i] --output (Join-Path $logs $label) --timeout $SuiteTimeoutSeconds --run-timeout $RunTimeoutSeconds
    if ($LASTEXITCODE -eq 130) { throw 'Isolated run cancelled; remaining hosts were not started.' }
    if ($LASTEXITCODE -ne 0) { $failed += $label }
}
Write-Host "Isolated evidence: $logs"
if ($failed.Count) { throw "Isolated regression failed: $($failed -join ', ')" }
