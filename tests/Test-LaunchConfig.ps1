param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$oldEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-config-' + [guid]::NewGuid().ToString('N'))
function Assert($ok, $message) { if (-not $ok) { throw $message } }
$source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
Assert (-not $errors.Count) 'Syntax errors'
foreach ($name in @('Get-LaunchSettingMap','Assert-ConfigFile','ConvertFrom-LaunchJson','Read-LaunchConfiguration','Get-LaunchSetting','Write-LaunchConfiguration')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$mocks = @'
function Find-OpenOcdInstallation { Add-Content calls.txt 'discovery'; $null }
function Find-CubeProgrammerCli { @() }
function Find-JLinkExe { $null }
function Find-StInfoExe { $null }
function Get-ToolVersion { 'fixture' }
function Get-JLinkProbes { @() }
function Get-InfoStLinkInventory { @{Entries=@(); Warning=$false; Source='fixture'} }
function Get-CimInstance { $null }
function Get-WmiObject { $null }
function Read-Host { 'q' }
function Start-Process { throw 'UNEXPECTED_PROCESS' }
function Invoke-WebRequest { throw 'UNEXPECTED_NETWORK' }
function Invoke-RestMethod { throw 'UNEXPECTED_NETWORK' }
function Invoke-Item { throw 'UNEXPECTED_BROWSER' }
'@
function Run($arguments, $exitCode) {
    $output = & $env:ComSpec /d /c "`"$root\flash.cmd`" $arguments" 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq $exitCode -and $output -notmatch 'UNEXPECTED_') "Unexpected result: $arguments : $output"
    return $output
}
function Snapshot {
    @(Get-ChildItem $CurrentDir -Force -File | Where-Object Name -ne 'calls.txt' | Sort-Object Name | Get-FileHash | Select-Object Path,Hash) | ConvertTo-Json -Compress
}
try {
    New-Item -ItemType Directory $root | Out-Null
    $CurrentDir = Join-Path $root 'working directory'
    New-Item -ItemType Directory $CurrentDir | Out-Null
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Missing injection boundary'
    $modified = $source.Insert($position, $mocks + "`r`n") -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $root 'flash.cmd'), $modified, (New-Object Text.UTF8Encoding($false)))
    Push-Location $CurrentDir
    try {
        $values = [ordered]@{ '.flash_engine'='JLINK'; '.probe_type'='JLINK'; '.stlink_serial'='0123456789ABCDEF01234567'; '.jlink_serial'='12345678'; '.jlink_device'='STM32F103CB'; '.openocd_target'='target/stm32f1x.cfg' }
        foreach ($name in $values.Keys) { Set-Content -LiteralPath $name -Value $values[$name] -Encoding UTF8 }
        $before = Snapshot
        foreach ($arguments in @('--help','--version','-Info -Lang en','-Setup -DryRun','-Setup','-Erase -DryRun -Engine OPENOCD -Target target/stm32f1x.cfg -Probe STLINK')) {
            Run $arguments 0 | Out-Null
            Assert ((Snapshot) -eq $before) "Read-only invocation changed legacy settings: $arguments"
        }
        Run '-Lang en' 1 | Out-Null # No HEX: migration precedes the operation, but no MCU is accessed.
        Assert (Test-Path .flash.json) 'Operational migration did not create JSON'
        foreach ($name in $values.Keys) {
            Assert (-not (Test-Path -LiteralPath $name)) "Legacy file retained: $name"
            Assert ((Get-LaunchSetting $name) -eq $values[$name]) "Migration lost $name"
        }
        Set-Content .flash_engine 'INVALID_LEGACY'
        Assert ((Get-LaunchSetting '.flash_engine') -eq 'JLINK') 'JSON did not take precedence'
        $before = Snapshot
        $plan = Run '-Erase -DryRun -Engine OPENOCD -Target target/stm32f1x.cfg -Probe STLINK -Lang en' 0
        Assert ($plan -match 'OPENOCD.*CLI' -and $plan -match 'STLINK.*CLI') 'CLI priority lost'
        Run '-Setup' 0 | Out-Null
        Assert ((Snapshot) -eq $before) 'JSON preview/cancel changed settings'
        $invalid = @('[]','[{"schemaVersion":1}]','null','{','{"schemaVersion":2}','{"schemaVersion":"1"}','{"schemaVersion":1,"probe":false}',
            '{"schemaVersion":1,"engine":"UNKNOWN"}','{"schemaVersion":1,"engine":"C:relative.exe"}','{"schemaVersion":1,"jlinkSerial":12345678}',
            '{"schemaVersion":1,"probe":"OTHER"}','{"schemaVersion":1,"extra":1}',
            '{"schemaVersion":1,"probe":"STLINK","probe":"JLINK"}','{"schemaVersion":1,"probe":"STLINK","Probe":"JLINK"}',
            '{"schemaVersion":1,"openocdTarget":"../bad.cfg"}','{"schemaVersion":1,"jlinkDevice":"bad name"}','{"schemaVersion":1,}', '{"schemaVersion":1 /* comment */}')
        foreach ($json in $invalid) {
            $failed = $false
            try { $null = ConvertFrom-LaunchJson $json } catch { $failed = $true }
            Assert $failed "Invalid JSON accepted: $json"
        }
        foreach ($json in @('{','{"schemaVersion":99}','{"schemaVersion":1,"probe":false}')) {
            Set-Content .flash.json $json -Encoding UTF8
            Remove-Item calls.txt -ErrorAction SilentlyContinue
            $before = Snapshot
            foreach ($language in @('en','ru')) {
                Run "--help -Lang $language" 0 | Out-Null
                Run "--version -Lang $language" 0 | Out-Null
                foreach ($arguments in @('-Info','-Erase -DryRun','')) {
                    $output = Run "$arguments -Lang $language" 1
                    $expected = if ($language -eq 'en') { 'Configuration\s+error' } else { [regex]::Unescape('\u041e\u0448\u0438\u0431\u043a\u0430') }
                    Assert ($output -match $expected) "Missing localized config error: $language $arguments : $output"
                }
            }
            Assert (-not (Test-Path calls.txt)) 'Invalid JSON reached discovery'
            Assert ((Snapshot) -eq $before) 'Invalid JSON was silently repaired'
        }
        Run '-ResetConfig -DryRun' 0 | Out-Null
        Assert (Test-Path .flash.json) 'Cleanup preview deleted JSON'
        Run '-ResetConfig' 0 | Out-Null
        Assert (-not (Test-Path .flash.json) -and -not (Test-Path .flash_engine)) 'Reset did not clear both formats'
        New-Item -ItemType Directory -Path .flash.json | Out-Null
        Run '-Info -Lang en' 1 | Out-Null
        Assert (Test-Path .flash.json -PathType Container) 'Invalid config directory was changed'
        Remove-Item -LiteralPath .flash.json
        foreach ($name in $values.Keys) { Set-Content -LiteralPath $name -Value $values[$name] -Encoding UTF8 }
        $locked = [IO.File]::Open((Join-Path $CurrentDir '.probe_type'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $failed = $false
        try { Write-LaunchConfiguration $values } catch { $failed = $true } finally { $locked.Dispose() }
        Assert $failed 'Legacy deletion failure was ignored'
        Assert ((Get-LaunchSetting '.jlink_serial') -eq '12345678') 'Partial cleanup lost authoritative JSON'
        Assert (Test-Path .probe_type) 'Locked legacy file unexpectedly deleted'
        Assert (@(Get-ChildItem -Force -Filter '.flash_config_*.tmp').Count -eq 0) 'Temporary configuration leaked'
        Write-Host 'Launch config: migration, read-only modes, validation, CLI priority and partial cleanup failure PASS'
    } finally { Pop-Location }
} finally {
    [Console]::OutputEncoding = $oldEncoding
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($root))) -ne $PSScriptRoot) { throw 'Invalid fixture root' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
