param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $repo 'flash.cmd') -Raw -Encoding UTF8
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$fixture = Join-Path $PSScriptRoot ('.tmp-jlink-failure-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
# TC-32: execute the entire PowerShell payload; only external boundaries are mocked.
$mocks = @'
function Find-JLinkExe { return (Join-Path $PWD 'mock-tool.exe') }
function Find-CubeProgrammerCli { return (Join-Path $PWD 'mock-tool.exe') }
function Find-OpenOcdInstallation { return $null }
function Find-StInfoExe { throw 'UNEXPECTED DISCOVERY' }
function Get-JLinkProbes { throw 'UNEXPECTED DISCOVERY' }
function Get-UsbStLinkProbes { throw 'UNEXPECTED USB' }
function Invoke-ProbeInventory { throw 'UNEXPECTED INVENTORY' }
function Invoke-ReadTool { throw 'UNEXPECTED READ' }
function Invoke-Download { throw 'UNEXPECTED DOWNLOAD' }
function Get-CimInstance { return $null }
function Read-Host { throw 'UNEXPECTED INPUT' }
function Invoke-Item { Add-Content -LiteralPath browser.txt -Value 'suppressed' }
function Start-Process {
    param($FilePath, [string[]]$ArgumentList, [switch]$NoNewWindow,
          [switch]$Wait, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
    if ($FilePath -ne (Join-Path $PWD 'mock-tool.exe')) { throw 'UNEXPECTED EXECUTABLE' }
    ConvertTo-Json -Compress -InputObject @($ArgumentList) | Add-Content -LiteralPath calls.jsonl
    Set-Content -LiteralPath $RedirectStandardOutput -Value 'Mock tool: Cannot connect to J-Link. Requested serial not found.'
    Set-Content -LiteralPath $RedirectStandardError -Value ''
    return [pscustomobject]@{ ExitCode = 1 }
}
'@
$position = $source.IndexOf('$CurrentDir     =')
Assert ($position -gt 0) 'Mock insertion point missing'
$mockSource = $source.Insert($position, $mocks + "`n")
# Avoid DNS queries for host metadata, which are unrelated to the tested operation.
$dns = '[System.Net.Dns]::GetHostEntry($MachineName)'
Assert ($mockSource.Contains($dns)) 'DNS boundary changed'
$mockSource = $mockSource.Replace($dns, '$null')
$guard = '(-not $Serial) -and'
Assert (([regex]::Matches($mockSource, [regex]::Escape($guard))).Count -eq 1) 'Retry guard changed'
try {
    foreach ($engine in @('JLINK', 'CUBEPROGRAMMER')) {
        foreach ($lang in @('en', 'ru')) {
            foreach ($mutated in @($false, $true)) {
                $work = Join-Path $fixture "$engine-$lang-$mutated"
                New-Item -ItemType Directory -Path $work | Out-Null
                $payload = if ($mutated) { $mockSource.Replace($guard, '$true -and') } else { $mockSource }
                $mockPath = Join-Path $work 'mock-flash.ps1'
                Set-Content -LiteralPath $mockPath -Value $payload -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $work 'mock-tool.exe') -Value 'Not an executable'
                Set-Content -LiteralPath (Join-Path $work 'firmware.hex') -Value ":020000040800F2`n:0400000001020304F2`n:00000001FF" -Encoding ASCII
                Set-Content -LiteralPath (Join-Path $work '.jlink_serial') -Value '87654321'
                Push-Location $work
                try {
                    $output = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $mockPath -HexFile firmware.hex -Engine $engine -Probe JLINK -Serial 12345678 -Device STM32F103C8 -Lang $lang 2>&1 | Out-String
                    $code = $LASTEXITCODE
                    Assert ($code -eq 1) "Expected operation failure: $engine/$lang : $output"
                    Assert (Test-Path calls.jsonl) "Engine not reached: $output"
                    $calls = @(Get-Content calls.jsonl | ForEach-Object {
                        [pscustomobject]@{ Arguments = (ConvertFrom-Json $_) }
                    })
                    $expectedCalls = if ($mutated) { 2 } else { 1 }
                    Assert ($calls.Count -eq $expectedCalls) "Unexpected retries: $engine/$lang/$mutated : $($calls.Count)"
                    if ($engine -eq 'JLINK') {
                        $usb = [array]::IndexOf($calls[0].Arguments, '-usb')
                        Assert ($usb -ge 0 -and $calls[0].Arguments[$usb + 1] -eq '12345678') 'Wrong J-Link serial'
                    } else {
                        Assert ($calls[0].Arguments -contains 'port=JLINK sn=12345678') 'Wrong Cube serial'
                    }
                    Assert (($calls[0].Arguments -join ' ') -notmatch '87654321') 'Saved serial overrides CLI'
                    if ($mutated) {
                        Assert (($calls[1].Arguments -join ' ') -notmatch '12345678|87654321|sn=|-usb') 'Mutation did not exercise serial-free retry'
                    }
                    $history = @(Get-ChildItem .history -Filter 'session_*.json')
                    Assert ($history.Count -eq 1) 'Failure history missing'
                    $entry = Get-Content $history[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    Assert ($entry.Success -eq $false -and $entry.Operation -eq 'flash') 'Failure reported as success'
                    Assert ((Get-Content flash_log.txt -Raw) -match 'Requested serial not found') 'Engine failure log missing'
                    Assert (Test-Path report.html) 'Failure report missing'
                    Assert ((@(Get-Content browser.txt)).Count -eq 1) 'Failure report opening not intercepted'
                    Assert (-not (Test-Path .jlink_flash.jlink)) 'Temporary Commander script left behind'
                } finally { Pop-Location }
            }
        }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'J-Link failure tests passed (two engines, RU/EN, retry-guard mutation controls).'
