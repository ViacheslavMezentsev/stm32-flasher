param(
    [ValidateSet('WorkingTree','Commit')][string]$Kind = 'WorkingTree',
    [ValidateSet('All','Validate','Regression')][string]$Stage = 'All',
    [ValidateSet('Full','Quick')][string]$Profile = 'Full',
    [string[]]$TestName,
    [string[]]$PowerShellExe = @('powershell','pwsh'),
    [string]$PythonExe = 'python',
    [string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$PythonExe = (Get-Command $PythonExe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if ($Stage -ne 'Validate') {
    if (-not $PowerShellExe.Count) { throw 'At least one PowerShell executable is required.' }
    $PowerShellExe = @($PowerShellExe | ForEach-Object { (Get-Command $_ -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source })
}
if (-not $RunDirectory) {
    $RunDirectory = Join-Path $repo ('tests/.tmp-ci-snapshots/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$RunDirectory = [IO.Path]::GetFullPath($RunDirectory)
$tool = Join-Path $PSScriptRoot 'snapshot.py'
$watch = [Diagnostics.Stopwatch]::StartNew()
& $PythonExe -B -X utf8 $tool create --source $repo --destination $RunDirectory --kind $Kind
if ($LASTEXITCODE -ne 0) { throw 'Snapshot creation failed; no tests started.' }
$watch.Stop()
$captureSeconds = $watch.Elapsed.TotalSeconds
$manifest = Join-Path $RunDirectory 'manifest.json'
$manifestHash = (Get-FileHash $manifest -Algorithm SHA256).Hash
$parameters = @{ Stage=$Stage; Profile=$Profile; PowerShellExe=$PowerShellExe; PythonExe=$PythonExe; LogDirectory=(Join-Path $RunDirectory 'logs') }
if ($PSBoundParameters.ContainsKey('TestName')) { $parameters.TestName = $TestName }
$outcome = [ordered]@{
    ManifestSha256=$manifestHash; StartedUtc=[DateTime]::UtcNow.ToString('o')
    FinishedUtc=$null; Status='Running'; Integrity='Pending'; Parameters=$parameters
    ShellVersion=$PSVersionTable.PSVersion.ToString(); Error=$null
    CaptureSeconds=$captureSeconds; ChecksSeconds=$null; VerifySeconds=$null
    Coverage='Selected checks only; inspect logs/*/run.json. Not hardware acceptance.'
    HostVersions=@(); PythonVersion=$null
}
$outcomePath = Join-Path $RunDirectory 'outcome.json'
$outcome | ConvertTo-Json -Depth 5 | Set-Content $outcomePath -Encoding UTF8
$failure = $null
Push-Location (Join-Path $RunDirectory 'source')
$watch.Restart()
try {
    $outcome.PythonVersion = (& $PythonExe --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Python version.' }
    if ($Stage -ne 'Validate') {
        foreach ($exe in $PowerShellExe) {
            $version = (& $exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { throw "Cannot read host version: $exe" }
            $outcome.HostVersions += [pscustomobject]@{ Exe=$exe; Version=$version }
        }
    }
    & (Join-Path $RunDirectory 'source/ci/Invoke-Local.ps1') @parameters 2>&1 | Tee-Object -FilePath (Join-Path $RunDirectory 'console.log')
} catch {
    $failure = $_.ToString()
} finally {
    $watch.Stop()
    $outcome.ChecksSeconds = $watch.Elapsed.TotalSeconds
    Pop-Location
    $watch.Restart()
    try {
        if ((Get-FileHash $manifest -Algorithm SHA256).Hash -ne $manifestHash) { throw 'Manifest changed during run.' }
        & $PythonExe -B -X utf8 $tool verify --destination $RunDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Snapshot source integrity failed.' }
        $outcome.Integrity = 'Passed'
    } catch {
        $outcome.Integrity = 'Failed'
        $failure = "$failure Integrity: $_"
    }
    $outcome.FinishedUtc = [DateTime]::UtcNow.ToString('o')
    $watch.Stop()
    $outcome.VerifySeconds = $watch.Elapsed.TotalSeconds
    $outcome.Status = if ($failure) { 'Failed' } else { 'Passed' }
    $outcome.Error = $failure
    $outcome | ConvertTo-Json -Depth 5 | Set-Content $outcomePath -Encoding UTF8
}
Write-Host "Snapshot evidence: $RunDirectory"
if ($failure) { throw $failure }
