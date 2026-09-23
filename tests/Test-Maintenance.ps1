param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repo 'flash.cmd'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput((Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
function Assert($condition, $message) { if (-not $condition) { throw $message } }
foreach ($name in @('ConvertFrom-JLinkProbeList', 'Select-ConnectedProbe', 'Test-EraseLog', 'Get-LogMatchValue', 'Get-Stm32Family', 'Invoke-EngineLogParser', 'Get-InfoEnginePath')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function T($key) { return $key }
function Read-Host { return $script:answer }
$probes = @(ConvertFrom-JLinkProbeList @'
Connecting to J-Link via USB...O.K.
J-Link>J-Link[0]: Connection: USB, Serial number: 69653773, ProductName: J-Link CE
J-Link[1]: Connection: USB, Serial number: 12345678, ProductName: J-Link PLUS
'@)
Assert ($probes.Count -eq 2) 'Both J-Link entries must be parsed'
$script:answer = '2'
Assert ((Select-ConnectedProbe $probes).Serial -eq '12345678') 'Second probe must be selected'
foreach ($bad in @('abc', '0', '3', '')) {
    $script:answer = $bad
    $rejected = $false
    try { Select-ConnectedProbe $probes | Out-Null } catch { $rejected = $true }
    Assert $rejected "Invalid choice accepted: $bad"
}
Assert ((Select-ConnectedProbe @($probes[0])).Serial -eq '69653773') 'Single probe must not prompt'
Assert (Test-EraseLog JLINK "Erasing device...`r`nErasing done.`r`n") 'J-Link success not detected'
Assert (-not (Test-EraseLog JLINK 'Erasing device... ERROR')) 'J-Link failure reported as success'
Assert (Test-EraseLog CUBEPROGRAMMER 'Mass erase successfully achieved') 'Cube success not detected'
Assert (-not (Test-EraseLog CUBEPROGRAMMER 'Sector erase successfully achieved')) 'Partial erase accepted'
Assert (Test-EraseLog OPENOCD "FLASH_ERASE_COMPLETE`n") 'OpenOCD success not detected'
Assert (-not (Test-EraseLog OPENOCD 'echo {FLASH_ERASE_COMPLETE}')) 'Echoed command accepted as success'
$patternsNode = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$EnginePatterns' }, $true)
. ([scriptblock]::Create($patternsNode.Extent.Text))
foreach ($voltageLine in @('Info : Target voltage: 3.234301', 'Info : target voltage: 3.234301')) {
    $parsed = Invoke-EngineLogParser "$voltageLine`n** Programming Finished **`n** Verified OK **" $EnginePatterns.OPENOCD
    Assert ($parsed.IsStlinkFound -and $parsed.IsProgrammed -and $parsed.IsVerified) 'OpenOCD success flags depend on letter case'
    Assert ($parsed.TargetVoltage -eq '3.234301 V') 'OpenOCD voltage parsing'
}

$fixture = Join-Path $repo ('.maintenance-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Run-Flash([string[]]$arguments) {
    $output = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath '$scriptPath')))" @arguments 2>&1
    Assert ($LASTEXITCODE -eq 0) ($output | Out-String)
    return ($output | Out-String)
}
Push-Location $fixture
try {
    $CurrentDir = $fixture
    $SelectedEngine = ''
    $cubeOne = Join-Path $fixture 'cube-one.exe'
    $cubeTwo = Join-Path $fixture 'cube-two.exe'
    $jlink = Join-Path $fixture 'JLink.exe'
    $OpenOcdExe = Join-Path $fixture 'openocd.exe'
    foreach ($path in @($cubeOne, $cubeTwo, $jlink, $OpenOcdExe)) { Set-Content -LiteralPath $path -Value 'fixture' }
    Assert ((Get-InfoEnginePath @($cubeOne, $cubeTwo) $jlink) -eq $cubeOne) 'Automatic engine marker must use the first CubeProgrammer'
    Set-Content -LiteralPath .flash_engine -Value $cubeTwo
    Assert ((Get-InfoEnginePath @($cubeOne, $cubeTwo) $jlink) -eq $cubeTwo) 'Saved executable marker'
    $SelectedEngine = 'OPENOCD'
    Assert ((Get-InfoEnginePath @($cubeOne, $cubeTwo) $jlink) -eq $OpenOcdExe) 'Explicit engine must override saved marker'
    $SelectedEngine = ''
    Remove-Item -LiteralPath .flash_engine
    Set-Content -LiteralPath first.hex -Value 'fixture'
    Set-Content -LiteralPath second.hex -Value 'fixture'
    Assert (-not (Get-InfoEnginePath @($cubeOne, $cubeTwo) $jlink)) 'Do not claim a selected engine when a menu is required'
    Remove-Item -LiteralPath first.hex, second.hex
    foreach ($name in @('.flash_engine', '.jlink_device', '.stlink_serial', '.probe_type', '.jlink_serial', '.openocd_target', 'flash_log.txt', 'report.html', 'firmware.hex', 'firmware.hex.sha256', 'notes.md')) {
        Set-Content -LiteralPath $name -Value 'fixture' -Encoding ASCII
    }
    foreach ($dir in @('.history', '.tools/stlink', '.tools/xpack-openocd-0.12.0-3', '.tools/user-tool')) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'keep.txt') -Value 'fixture'
    }
    $before = @(Get-ChildItem -Recurse -Force -File | Get-FileHash | Select-Object Path, Hash | ConvertTo-Json)
    Run-Flash @('-Clean', '-DryRun') | Out-Null
    $after = @(Get-ChildItem -Recurse -Force -File | Get-FileHash | Select-Object Path, Hash | ConvertTo-Json)
    Assert (($before -join '') -eq ($after -join '')) 'Cleanup preview changed files'
    Run-Flash @('-ResetConfig') | Out-Null
    Assert (-not (Test-Path .jlink_device)) 'Configuration was not removed'
    Assert (Test-Path .history/keep.txt) 'ResetConfig removed history'
    Assert (Test-Path report.html) 'ResetConfig removed report'
    $preview = Run-Flash @('-Erase', '-Engine', 'OPENOCD', '-Probe', 'STLINK', '-Target', 'target/stm32f1x.cfg', '-DryRun')
    Assert ($preview -match 'flash erase_sector') 'Erase command not generated without HEX selection'
    Assert (-not (Test-Path .flash_engine)) 'Erase preview saved engine'
    Assert (-not (Test-Path .openocd_target)) 'Erase preview saved target'
    Run-Flash @('-Clean') | Out-Null
    foreach ($name in @('.history', 'report.html', 'flash_log.txt', '.tools/stlink', '.tools/xpack-openocd-0.12.0-3')) {
        Assert (-not (Test-Path -LiteralPath $name)) "Cleanup left $name"
    }
    foreach ($name in @('firmware.hex', 'firmware.hex.sha256', 'notes.md', '.tools/user-tool/keep.txt')) {
        Assert (Test-Path -LiteralPath $name) "Cleanup removed user file $name"
    }
} finally {
    Pop-Location
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Maintenance tests passed.'
