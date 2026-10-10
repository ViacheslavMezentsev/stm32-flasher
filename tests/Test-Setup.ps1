param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $PSScriptRoot ('.tmp-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Snapshot {
    @(Get-ChildItem -LiteralPath $fixture -Force -File | Where-Object { $_.Name -notin @('flash.cmd','setup.cmd') } |
        Sort-Object Name | Get-FileHash | Select-Object Path,Hash) | ConvertTo-Json -Compress
}
function Run-Setup($answers, $arguments = '-Lang en', $code = 0) {
    $env:SETUP_TEST_ANSWERS = ConvertTo-Json -Compress -InputObject @($answers)
    $output = & $env:ComSpec /d /c "setup.cmd $arguments" 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq $code) "Unexpected exit for $arguments : $output"
    return $output
}
$mocks = @'
$script:setupAnswers = New-Object 'Collections.Generic.Queue[string]'
foreach ($answer in @((ConvertFrom-Json $env:SETUP_TEST_ANSWERS))) { $script:setupAnswers.Enqueue([string]$answer) }
function Read-Host { if ($DryRun) { throw 'UNEXPECTED_INPUT' }; if (-not $script:setupAnswers.Count) { throw 'MISSING_TEST_ANSWER' }; return $script:setupAnswers.Dequeue() }
function Find-CubeProgrammerCli { if ($DryRun) { throw 'UNEXPECTED_DISCOVERY' }; return (Join-Path $CurrentDir 'cube.exe') }
function Find-JLinkExe { if ($DryRun) { throw 'UNEXPECTED_DISCOVERY' }; return (Join-Path $CurrentDir 'JLink.exe') }
function Get-InfoStLinkInventory {
    if ($DryRun) { throw 'UNEXPECTED_USB' }
    return @{ Warning = $false; Entries = @(
        @{ Type = 'STLINK'; Serial = '111111111111111111111111'; Family = 'Board A' },
        @{ Type = 'STLINK'; Serial = '222222222222222222222222'; Family = 'Board B' }) }
}
function Get-JLinkProbes {
    if ($DryRun) { throw 'UNEXPECTED_USB' }
    return @(@{ Type = 'JLINK'; Serial = '12345678'; Family = 'Probe A' }, @{ Type = 'JLINK'; Serial = '87654321'; Family = 'Probe B' })
}
function Get-StInfoProbeInfo { throw 'UNEXPECTED_MCU' }
function Invoke-ReadTool { throw 'UNEXPECTED_MCU' }
function Invoke-Download { throw 'UNEXPECTED_NETWORK' }
'@
try {
    $source = Get-Content -LiteralPath (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Missing injection point'
    $modified = $source.Insert($position, $mocks + "`r`n")
    $modified = $modified -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $fixture 'flash.cmd'), $modified, (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath (Join-Path $repo 'bin/setup.cmd') -Destination $fixture
    foreach ($name in @('.flash_engine','.probe_type','.stlink_serial','.jlink_serial','.jlink_device','.openocd_target','firmware.hex','report.html','flash_log.txt','cube.exe')) {
        Set-Content -LiteralPath (Join-Path $fixture $name) -Value 'sentinel'
    }
    Push-Location $fixture
    try {
        $before = Snapshot
        foreach ($argsText in @('-DryRun -Lang en','-DryRun -Lang ru','--help','--version')) {
            $output = Run-Setup @() $argsText
            Assert ($output -notmatch 'UNEXPECTED_') $output
            Assert ((Snapshot) -eq $before) 'Read-only setup changed files'
        }
        foreach ($answers in @(@('q'), @('3','q'), @('2','1','q'), @('3','2','n'))) {
            Run-Setup $answers | Out-Null
            Assert ((Snapshot) -eq $before) 'Cancellation changed files'
        }
        Run-Setup @('invalid') '-Lang en' 1 | Out-Null
        Run-Setup @('4','1','bad device') '-Lang en' 1 | Out-Null
        Run-Setup @('2','1','../bad.cfg') '-Lang en' 1 | Out-Null
        foreach ($argsText in @('-Erase','-Engine OPENOCD','-ProbeTarget','-Silent','-HexFile firmware.hex')) {
            Run-Setup @() $argsText 1 | Out-Null
        }
        Assert ((Snapshot) -eq $before) 'Invalid input changed files'
        Run-Setup @('3','3','y') | Out-Null
        Assert ((Get-Content .stlink_serial -Raw).Trim() -eq '222222222222222222222222') 'Wrong ST-Link'
        Assert ((Get-Content .probe_type -Raw).Trim() -eq 'STLINK') 'Wrong type'
        Assert (-not (Test-Path .jlink_serial)) 'Stale J-Link serial retained'
        Assert (-not (Test-Path .jlink_device)) 'Stale J-Link device retained'
        Run-Setup @('4','1','STM32F103CB','y') '-Lang ru' | Out-Null
        Assert (-not (Test-Path .stlink_serial)) 'Stale ST-Link serial retained'
        Assert (-not (Test-Path .jlink_serial)) 'Auto must not pin a serial'
        Assert ((Get-Content .flash_engine -Raw).Trim() -eq 'JLINK') 'Wrong engine'
        Assert ((Get-Content .jlink_device -Raw).Trim() -eq 'STM32F103CB') 'Wrong device'
        Run-Setup @('1','1','','y') | Out-Null
        Assert (-not (Test-Path .flash_engine)) 'Auto engine must remove override'
        Assert (-not (Test-Path .openocd_target)) 'Blank target must defer detection'
        foreach ($name in @('firmware.hex','report.html','flash_log.txt')) {
            Assert ((Get-Content $name -Raw).Trim() -eq 'sentinel') "User artifact changed: $name"
        }
        # Exercise rollback and unpinned selection using production functions.
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
        Assert (-not $errors.Count) 'Parse error'
        foreach ($name in @('Save-SetupSettings','Select-UnpinnedProbe','Select-ConnectedProbe')) {
            $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            . ([scriptblock]::Create($node.Extent.Text))
        }
        $CurrentDir = $fixture
        function T($key) { $key }
        function Read-Host { '2' }
        function Get-JLinkProbes { @(@{Serial='12345678';Type='JLINK';Family='A'},@{Serial='87654321';Type='JLINK';Family='B'}) }
        Assert ((Select-UnpinnedProbe 'JLINK') -eq '87654321') 'Unpinned selection must use menu'
        function Get-JLinkProbes { @(@{Serial='12345678';Type='JLINK';Family='A'}) }
        Assert ((Select-UnpinnedProbe 'JLINK') -eq '') 'Single probe need not be pinned'
        function Find-CubeProgrammerCli { @() }
        function Get-InfoStLinkInventory { @{ Warning=$false; Entries=@(@{Serial='111111111111111111111111';Type='STLINK';Family='A'},@{Serial='222222222222222222222222';Type='STLINK';Family='B'}) } }
        Assert ((Select-UnpinnedProbe 'STLINK') -eq '222222222222222222222222') 'ST-Link menu selection'
        function Write-Info { }
        function Find-JLinkExe { 'JLink.exe' }
        function Save-LaunchSetting { }
        $initStart = $source.IndexOf('$SelectedProbeSerial = ""')
        $initEnd = $source.IndexOf('$PsVerStr =', $initStart)
        $engineStart = $source.IndexOf('$EngineCfgPath =')
        $engineEnd = $source.IndexOf('if ($NoFirmware -and $SelectedEngine', $engineStart)
        Assert ($initStart -gt 0 -and $engineEnd -gt $engineStart) 'Missing engine selection blocks'
        $Probe = ''; $Engine = ''; $FreshProbeSelection = $false; $DryRun = $false; $AutoFlash = $true; $NoFirmware = $false
        foreach ($type in @('STLINK','JLINK')) {
            Set-Content -LiteralPath .probe_type -Value $type
            $SelectedEngine = ''
            . ([scriptblock]::Create($source.Substring($initStart, $initEnd - $initStart)))
            Assert ($ProbeSpecified -and $SelectedProbeType -eq $type) 'Saved type must precede engine selection'
            . ([scriptblock]::Create($source.Substring($engineStart, $engineEnd - $engineStart)))
            $expected = if ($type -eq 'STLINK') { 'OPENOCD' } else { 'JLINK' }
            Assert ($SelectedEngine -eq $expected) 'Automatic engine must match saved probe type'
        }
        $before = Snapshot
        $script:failedOnce = $false
        function Remove-Item {
            param($LiteralPath, [switch]$Force)
            if (-not $script:failedOnce) { $script:failedOnce = $true; throw 'WRITE_FAILURE' }
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force
        }
        $failed = $false
        try { Save-SetupSettings @{'.flash_engine'='OPENOCD'; '.probe_type'='' } } catch { $failed = $true }
        Assert $failed 'Injected write failure not propagated'
        Assert ((Snapshot) -eq $before) 'Rollback did not restore exact bytes'
        Remove-Item Function:\Remove-Item
        Write-Output 'Setup tests passed without hardware.'
    } finally { Pop-Location }
} finally {
    Remove-Item Env:\SETUP_TEST_ANSWERS -ErrorAction SilentlyContinue
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -ne $PSScriptRoot) { throw 'Invalid fixture path' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $fixture -Recurse -Force
}
