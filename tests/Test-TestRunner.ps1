$ErrorActionPreference = 'Stop'
$hostExe = (Get-Process -Id $PID).Path
$root = Join-Path $PSScriptRoot ('.tmp-runner-' + [guid]::NewGuid().ToString('N'))
function Assert($ok, $message) { if (-not $ok) { throw $message } }
New-Item -ItemType Directory -Path $root | Out-Null
$process = $null
try {
    Copy-Item (Join-Path $PSScriptRoot 'Invoke-Tests.ps1') $root
    $streamTest = @'
Write-Output 'STREAM_READY'
$limit = [DateTime]::UtcNow.AddSeconds(15)
while (-not (Test-Path (Join-Path $PSScriptRoot 'ack'))) {
    if ([DateTime]::UtcNow -gt $limit) { throw 'Output was buffered until completion' }
    Start-Sleep -Milliseconds 100
}
Write-Output 'STREAM_DONE'
'@
    Set-Content (Join-Path $root 'Test-01.ps1') $streamTest -Encoding ASCII
    Set-Content (Join-Path $root 'Test-02.ps1') "[Console]::Error.WriteLine('EXPECTED_STDERR'); exit 7" -Encoding ASCII
    Set-Content (Join-Path $root 'Test-03.ps1') "Write-Output 'AFTER_FAILURE'" -Encoding ASCII
    $stdout = Join-Path $root 'stdout.log'
    $stderr = Join-Path $root 'stderr.log'
    $logs = Join-Path $root 'logs'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'Invoke-Tests.ps1') + '" -LogDirectory "' + $logs + '"'
    $process = Start-Process -FilePath $hostExe -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $limit = [DateTime]::UtcNow.AddSeconds(12)
    $ready = $false
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $limit) {
        if ((Get-Content $stdout -Raw -ErrorAction SilentlyContinue) -match 'STREAM_READY') { $ready = $true; break }
        Start-Sleep -Milliseconds 100
    }
    Assert $ready 'Runner did not stream output before suite completion'
    Assert ((Get-Content (Join-Path $logs 'Test-01.log') -Raw) -match 'STREAM_READY') 'Live log was not flushed'
    Set-Content (Join-Path $root 'ack') 'continue' -Encoding ASCII
    Assert ($process.WaitForExit(20000)) 'Runner did not finish'
    Assert ($process.ExitCode -ne 0) 'Failed suite was masked'
    $results = Get-Content (Join-Path $logs 'results.json') -Raw | ConvertFrom-Json
    Assert ($results.Count -eq 3) 'Runner stopped before last suite'
    Assert ($results[0].Passed -and $results[1].ExitCode -eq 7 -and -not $results[1].Passed -and $results[2].Passed) 'Wrong exit codes'
    foreach ($entry in $results) { Assert ($entry.DurationSeconds -gt 0) 'Missing duration' }
    $output = Get-Content $stdout -Raw
    Assert ($output -match 'STREAM_DONE' -and $output -match 'EXPECTED_STDERR' -and $output -match 'AFTER_FAILURE') 'Output missing'
    Assert ($output -match 'Test-02.ps1: FAIL' -and $output -match 'Test-03.ps1: PASS') 'Missing progress summaries'
    Assert ((Get-Content (Join-Path $logs 'Test-02.log') -Raw) -match 'EXPECTED_STDERR') 'stderr missing from log'
} finally {
    if ($process) {
        if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
        $process.Dispose()
    }
    # The handshake child has its own 15-second deadline even if the runner fails.
    if (-not (Test-Path (Join-Path $root 'ack'))) {
        Set-Content (Join-Path $root 'ack') 'cleanup' -Encoding ASCII
        Start-Sleep -Seconds 2
    }
    $resolved = [IO.Path]::GetFullPath($root)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Test runner streaming, logs, durations and failure propagation passed.'
