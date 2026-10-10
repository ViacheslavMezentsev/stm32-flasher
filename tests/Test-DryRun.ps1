param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
# TC-18, TC-19, TC-26..TC-31, TC-34, TC-35: real CMD entry, mocked external boundaries.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
function Assert($ok, $message) { if (-not $ok) { throw $message } }
$fixture = Join-Path $PSScriptRoot ('.tmp-dryrun-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$guards = @'
function Stop-Forbidden { [Console]::Error.WriteLine('FORBIDDEN SIDE EFFECT'); exit 97 }
foreach ($name in @('Start-Process','Invoke-Item','Invoke-WebRequest','Invoke-RestMethod',
    'Invoke-Download','Invoke-ReadTool','Invoke-ProbeInventory','Get-JLinkProbes',
    'Get-StInfoProbeInfo','Ensure-StInfoExe','Get-UsbStLinkProbes','Get-CimInstance',
    'Get-WmiObject','Read-Host','Set-Content','Add-Content','Out-File','New-Item',
    'Remove-Item','Copy-Item','Move-Item','Save-LaunchSetting','Save-HistoryArtifacts',
    'Write-IntelHex','Get-ToolVersion')) {
    Set-Item -Path "function:$name" -Value { Stop-Forbidden }
}
function Find-CubeProgrammerCli { return @() }
function Find-JLinkExe { return $null }
function Find-OpenOcdInstallation { return $null }
'@
$position = $source.IndexOf('$CurrentDir     =')
Assert ($position -gt 0) 'Mock insertion point missing'
$source = $source.Insert($position, $guards + "`n")
# Fail closed if preview falls through into normal execution (before DNS/tools).
$source = $source.Replace('$OpenOcdUrl     =', 'Stop-Forbidden; $OpenOcdUrl     =')
$source = $source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
function Snapshot {
    @(Get-ChildItem $fixture -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { "DIR $($_.FullName)" } else { "$($_.FullName) $((Get-FileHash -LiteralPath $_.FullName).Hash)" }
    }) -join "`n"
}
function Run-Preview($arguments, $expected = 0, $wrapper = 'flash') {
    $before = Snapshot
    $out = & $env:ComSpec /d /c "`"$fixture\$wrapper.cmd`" $arguments" 2>&1 | Out-String
    $code = $LASTEXITCODE
    Assert ($code -eq $expected) "Exit $code expected $expected : $arguments`n$out"
    Assert ($out -notmatch 'FORBIDDEN SIDE EFFECT') "Side effect: $arguments"
    Assert ((Snapshot) -ceq $before) "Files changed: $arguments"
    return $out
}
try {
    [IO.File]::WriteAllText((Join-Path $fixture 'flash.cmd'), $source, (New-Object Text.UTF8Encoding($false)))
    foreach ($wrapper in @('erase','backup','info','forget')) { Copy-Item (Join-Path $repo "bin/$wrapper.cmd") $fixture }
    Set-Content (Join-Path $fixture 'firmware.hex') ":020000040800F2`n:0400000001020304F2`n:00000001FF" -Encoding ASCII
    Push-Location $fixture
    try {
        foreach ($lang in @('en','ru')) {
            foreach ($engine in @('OPENOCD','CUBEPROGRAMMER','JLINK')) {
                $common = "-DryRun -Lang $lang -Engine $engine -Target target/stm32f1x.cfg -Device STM32F103C8"
                $preview = Run-Preview "$common -HexFile firmware.hex"
                Assert ($preview -match 'DRY RUN' -and $preview -match 'firmware.hex.*CLI') 'Plan identity or input source missing'
                if ($lang -eq 'en') { Assert ($preview -match 'devices not queried' -and $preview -match 'operation not performed') 'Deferred selection disclaimer missing' }
                Run-Preview $common 0 'erase' | Out-Null
                Run-Preview "$common -Size 65536" 0 'backup' | Out-Null
                Run-Preview $common 0 'info' | Out-Null
                Run-Preview "$common -ProbeTarget" 0 'info' | Out-Null
            }
            Run-Preview "-DryRun -Lang $lang" 0 'forget' | Out-Null
            Run-Preview "-DryRun -ResetConfig -Lang $lang" | Out-Null
        }
        $missing = Run-Preview '-DryRun -Lang en -Engine JLINK -Device STM32F103C8' 1 'backup'
        Assert ($missing -match 'Example.*-Engine "JLINK".*-Size <value>' -and $missing -match 'operation not performed') 'Missing size guidance'
        $infoPlan = Run-Preview '-DryRun -Lang en' 0 'info'
        Assert ($infoPlan -notmatch 'installation/download needed') 'Unknown engine incorrectly reported as missing tool'
        Run-Preview '-DryRun -Engine JLINK' 1 'erase' | Out-Null
        Run-Preview '-DryRun -Engine OPENOCD' 1 'erase' | Out-Null
        Run-Preview '-DryRun -Engine JLINK -Device STM32F103C8 -Size nope' 1 'backup' | Out-Null
        Run-Preview '-DryRun -Engine JLINK -Device STM32F103C8 -Size 0' 1 'backup' | Out-Null
        Run-Preview '-DryRun -Engine JLINK -Device STM32F103C8 -Size 67108865' 1 'backup' | Out-Null
        Run-Preview '-DryRun -Engine JLINK -Device STM32F103C8 -Size 16 -Address 0xFFFFFFFF' 1 'backup' | Out-Null
        Run-Preview '-DryRun -Engine OPENOCD -HexFile missing.hex' 1 | Out-Null
        Set-Content second.hex ':00000001FF'
        Run-Preview '-DryRun -Engine OPENOCD -Target target/stm32f1x.cfg' 1 | Out-Null
        Remove-Item second.hex
        Set-Content .flash_engine 'JLINK'
        Set-Content .jlink_device 'STM32F103C8'
        Set-Content .jlink_serial '87654321'
        $plan = Run-Preview '-DryRun -Lang en -Serial 12345678'
        Assert ($plan -match '12345678.*CLI' -and $plan -match 'STM32F103C8.*saved') 'Value sources missing'
        $hash = (Get-FileHash firmware.hex -Algorithm SHA256).Hash
        Set-Content firmware.hex.sha256 "$hash *firmware.hex"
        Run-Preview '-DryRun' | Out-Null
        Set-Content firmware.hex.sha256 ('0' * 64)
        Run-Preview '-DryRun' 1 | Out-Null
        Remove-Item firmware.hex.sha256
        Run-Preview '-DryRun -Sha256 invalid' 1 | Out-Null
        $valid = Get-Content firmware.hex -Raw
        foreach ($bad in @(':00000001FF', $valid.Replace('0304F2','0304F3'), $valid.Replace(':00000001FF',''), ($valid + "`n:00000001FF"), ':GG', ':0100000000FF', $valid.Replace(':0400000001020304F2', ':0300000001020304F3'), $valid.Replace(':020000040800F2', ':020000060800F0'), $valid.Replace(':020000040800F2', ':0100000408F3'))) {
            Set-Content firmware.hex $bad
            Run-Preview '-DryRun' 1 | Out-Null
        }
        Set-Content firmware.hex $valid
        Copy-Item firmware.hex 'firmware with spaces.hex'
        Run-Preview '-DryRun -HexFile "firmware with spaces.hex" -Serial 12345678' | Out-Null
        Remove-Item 'firmware with spaces.hex'
        Run-Preview '-DryRun -Engine UNKNOWN' 1 | Out-Null
        Run-Preview '-DryRun -Probe WRONG' 1 | Out-Null
        Run-Preview '-DryRun -Engine JLINK -Probe STLINK' 1 | Out-Null
        Run-Preview '-DryRun -Engine OPENOCD -Probe JLINK -Target target/stm32f1x.cfg' 1 | Out-Null
        Run-Preview '-DryRun -Size 65536 -Output firmware.hex' 1 'backup' | Out-Null
        Run-Preview '-DryRun -Erase -Backup' 1 | Out-Null
        Run-Preview '-DryRun --version' | Out-Null
        Run-Preview '-DryRun --help' 0 'erase' | Out-Null
    } finally { Pop-Location }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'DryRun tests passed without tools, USB, prompts or file changes.'
