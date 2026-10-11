param(
    [string]$PowerShellExe = (Get-Process -Id $PID).Path,
    [string]$LogDirectory = (Join-Path $PSScriptRoot '.tmp-ci-logs'),
    [string[]]$TestName,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$PowerShellExe = (Get-Command $PowerShellExe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' -File | Sort-Object Name)
if (-not $tests.Count) { throw 'No regression tests found.' }
$discoveredCount = $tests.Count
if ($PSBoundParameters.ContainsKey('TestName')) {
    if (-not $TestName.Count) { throw 'TestName cannot be empty.' }
    foreach ($name in $TestName) {
        if ($name -notin $tests.Name) { throw "Unknown test name: $name. Use exact Test-*.ps1 filenames, without paths or wildcards." }
    }
    $tests = @($tests | Where-Object { $_.Name -in $TestName })
}
$partial = $tests.Count -ne $discoveredCount
if ($List) { $tests.Name; return }
Write-Host "Selected $($tests.Count)/$discoveredCount suites; partial=$partial"
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$run = [ordered]@{
    StartedUtc = [DateTime]::UtcNow.ToString('o'); FinishedUtc = $null
    PowerShellExe = $PowerShellExe; DiscoveredCount = $discoveredCount
    SelectedTests = @($tests.Name); Partial = $partial; Status = 'Running'
}
$run | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $LogDirectory 'run.json') -Encoding UTF8
$results = @()
foreach ($test in $tests) {
    Write-Host "Running $($test.Name) with $PowerShellExe"
    $log = Join-Path $LogDirectory ($test.BaseName + '.log')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $writer = New-Object IO.StreamWriter($log, $false, (New-Object Text.UTF8Encoding($false)))
    $writer.AutoFlush = $true
    try {
        # PS5.1 wraps native stderr as ErrorRecord; exit code determines success.
        $ErrorActionPreference = 'Continue'
        & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $test.FullName 2>&1 |
            ForEach-Object {
                $line = $_.ToString()
                $writer.WriteLine($line)
                Write-Host $line
            } -ErrorAction Stop
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
        $watch.Stop()
        $writer.Dispose()
    }
    $seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
    $status = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}: {1} ({2:F3} s, exit {3})" -f $test.Name, $status, $seconds, $code)
    $results += [pscustomobject]@{ Test = $test.Name; ExitCode = $code; Passed = ($code -eq 0); DurationSeconds = $seconds }
}
ConvertTo-Json -InputObject @($results) | Set-Content -LiteralPath (Join-Path $LogDirectory 'results.json') -Encoding UTF8
$run.FinishedUtc = [DateTime]::UtcNow.ToString('o')
$run.Status = if (@($results | Where-Object { -not $_.Passed }).Count) { 'Failed' } else { 'Passed' }
$run | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $LogDirectory 'run.json') -Encoding UTF8
$results | Format-Table -AutoSize | Out-Host
if (@($results | Where-Object { -not $_.Passed }).Count) { throw 'Regression tests failed. See logs and results.json.' }
if ($partial) { Write-Host "Selected $($tests.Count)/$discoveredCount suites passed. PARTIAL coverage, not full acceptance." }
else { Write-Host "All $($tests.Count) test suites passed." }
