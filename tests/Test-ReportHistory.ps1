param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $repo 'flash.cmd') -Raw -Encoding UTF8
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$fixture = Join-Path $PSScriptRoot ('.tmp-report-history-' + [guid]::NewGuid().ToString('N'))

# Only external boundaries are replaced; operation, parsing, HTML and history code stay real.
$mocks = @'
function Stop-Unexpected($name) { [Console]::Error.WriteLine("UNEXPECTED: $name"); exit 97 }
function Find-CubeProgrammerCli { Join-Path $PWD 'mock-tool.exe' }
function Find-JLinkExe { return $null }
function Find-OpenOcdInstallation { return $null }
function Find-StInfoExe { return $null }
function Invoke-ProbeInventory { return $null }
function Get-JLinkProbes { [pscustomobject]@{ Serial = '12345678'; Type = 'JLINK'; Family = 'Fixture' } }
function Get-UsbStLinkProbes { return @() }
function Get-CimInstance { return $null }
function Invoke-Download { Stop-Unexpected 'download' }
function Read-Host { Stop-Unexpected 'input' }
function Invoke-Item($path) { Add-Content -LiteralPath browser.txt -Value $path }
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$NoNewWindow, [switch]$Wait,
        [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
    if ($FilePath -ne (Join-Path $PWD 'mock-tool.exe')) { Stop-Unexpected 'executable' }
    Add-Content -LiteralPath calls.txt -Value 'write'
    $log = "STM32CubeProgrammer v2.23.0`nVoltage : 3.30V`nDevice ID : 0x410`nFixture <tag> & log"
    if ($env:FLASH_REPORT_CASE -ne 'missing') {
        $log += "`nFile download complete`nDownload verified successfully`nMass erase successfully achieved"
    }
    Set-Content -LiteralPath $RedirectStandardOutput -Value $log
    Set-Content -LiteralPath $RedirectStandardError -Value ''
    [pscustomobject]@{ ExitCode = $(if ($env:FLASH_REPORT_CASE -eq 'error') { 7 } else { 0 }) }
}
function Invoke-ReadTool($exe, $arguments) {
    if ($exe -ne (Join-Path $PWD 'mock-tool.exe') -or $arguments -notcontains '-u') { Stop-Unexpected 'read' }
    Add-Content -LiteralPath calls.txt -Value 'read'
    [IO.File]::WriteAllBytes($arguments[-1].Trim('"'), (New-Object byte[] 16))
    [pscustomobject]@{
        ExitCode = $(if ($env:FLASH_REPORT_CASE -eq 'error') { 7 } else { 0 })
        Log = "Voltage : 3.30V`nDevice ID : 0x410`nData read successfully`nFixture <tag> & log"
    }
}
'@
$position = $source.IndexOf('$CurrentDir     =')
Assert ($position -gt 0) 'Cannot inject mocks'
$dns = '[System.Net.Dns]::GetHostEntry($MachineName)'
Assert ($source.Contains($dns)) 'DNS boundary changed'
$mockSource = $source.Insert($position, $mocks + "`n").Replace($dns, '$null')
$oldCase = $env:FLASH_REPORT_CASE
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    foreach ($lang in @('en', 'ru')) {
        foreach ($operation in @('flash', 'erase', 'backup')) {
            $cases = @('good', 'error')
            if ($operation -ne 'backup') { $cases += 'missing' }
            foreach ($case in $cases) {
                $id = "$operation-$lang-$case"
                $work = Join-Path $fixture $id
                New-Item -ItemType Directory -Path $work | Out-Null
                $mockPath = Join-Path $work 'mock-flash.ps1'
                Set-Content -LiteralPath $mockPath -Value $mockSource -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $work 'mock-tool.exe') -Value 'not executable'
                Set-Content -LiteralPath (Join-Path $work 'firmware.hex') -Value ":020000040800F2`n:0400000001020304F2`n:00000001FF"
                $arguments = @('-Engine', 'CUBEPROGRAMMER', '-Probe', 'JLINK', '-Serial', '12345678', '-Lang', $lang)
                switch ($operation) {
                    flash { $arguments += @('-HexFile', 'firmware.hex') }
                    erase { $arguments += '-Erase' }
                    backup { $arguments += @('-Backup', '-Size', '16', '-Output', 'backups/copy.hex') }
                }
                $env:FLASH_REPORT_CASE = $case
                Push-Location $work
                try {
                    $output = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $mockPath @arguments 2>&1 | Out-String
                    $exitCode = $LASTEXITCODE
                    $success = $case -eq 'good'
                    Assert ($exitCode -eq $(if ($success) { 0 } else { 1 })) "$id exit: $output"
                    Assert (@(Get-Content calls.txt).Count -eq 1) "$id unexpected engine calls"
                    $sessions = @(Get-ChildItem .history -Filter 'session_*.json')
                    Assert ($sessions.Count -eq 1) "$id history count"
                    $jsonOptions = @{}
                    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOptions.DateKind = 'String' }
                    $entry = Get-Content $sessions[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json @jsonOptions
                    Assert ($entry.Success -eq $success -and $entry.Operation -eq $operation) "$id history result"
                    Assert ($entry.EngineName -eq 'STM32CubeProgrammer') "$id engine"
                    Assert ($entry.OperationDuration -match '^\d{2}:\d{2}:\d{2}\.\d{3}$') "$id duration"
                    Assert (([timespan]::Parse($entry.OperationDuration)).TotalMilliseconds -ge 0) "$id negative duration"
                    $utc = [DateTimeOffset]::Parse($entry.TimestampUtc)
                    $local = [DateTimeOffset]::Parse($entry.TimestampLocal)
                    Assert ($utc.Offset -eq [TimeSpan]::Zero -and [Math]::Abs(($utc - $local).TotalSeconds) -lt 1) "$id timestamps: $($entry.TimestampUtc) / $($entry.TimestampLocal) / $utc"
                    $html = Get-Content report.html -Raw -Encoding UTF8
                    Assert ($html.Contains("<html lang=`"$lang`">")) "$id language"
                    Assert ($html.Contains($entry.ResultText) -and $html.Contains($entry.OperationDuration)) "$id report result/duration"
                    Assert ($html.Contains('Fixture &lt;tag&gt; &amp; log') -and -not $html.Contains('Fixture <tag>')) "$id HTML log escaping"
                    $toolCode = if ($case -eq 'error') { if ($operation -eq 'backup') { 1 } else { 7 } } else { 0 }
                    $exitRow = '</code></td></tr>\s*<tr><th>[^<]+</th><td><span class=' + "'(ok|err)'>&#1000[37]; $toolCode(?:\s|<)"
                    Assert ($html -match $exitRow) "$id report exit code"
                    $index = Get-Content .history/index.html -Raw -Encoding UTF8
                    foreach ($name in @($entry.ReportFile, $entry.LogFile)) {
                        Assert ($index.Contains("href='$name'")) "$id index link"
                        Assert (Test-Path -LiteralPath (Join-Path '.history' $name) -PathType Leaf) "$id missing archive"
                    }
                    Assert ((Get-FileHash report.html).Hash -eq (Get-FileHash (Join-Path '.history' $entry.ReportFile)).Hash) "$id archived report differs"
                    Assert ((Get-Content (Join-Path '.history' $entry.LogFile) -Raw).Contains('Fixture <tag> & log')) "$id archived log"
                    Assert ($index.Contains($entry.ResultText) -and $index.Contains($entry.OperationDuration)) "$id index content"
                    Assert ((Test-Path browser.txt) -eq (-not $success)) "$id browser policy"
                    if (-not $success) {
                        $opened = @(Get-Content browser.txt)
                        Assert ($opened.Count -eq 1 -and (Split-Path -Leaf $opened[0]) -eq 'report.html') "$id browser target"
                    }
                    if ($operation -eq 'backup') {
                        Assert ((Test-Path backups/copy.hex) -eq $success) "$id backup publication"
                        Assert ((Test-Path backups/copy.hex.sha256) -eq $success) "$id checksum publication"
                    }
                    Write-Host "$id PASS"
                } finally { Pop-Location }
            }
        }
    }
} finally {
    $env:FLASH_REPORT_CASE = $oldCase
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Report/history tests passed.'
