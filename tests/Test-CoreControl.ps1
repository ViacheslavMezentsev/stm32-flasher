param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-core-' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:FLASH_CORE_ROOT; $oldMode = $env:FLASH_CORE_MODE; $oldCommand = $env:FLASH_CORE_COMMAND
function Assert($ok, $message) { if (-not $ok) { throw $message } }
$sourceText = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
$parserStart = $sourceText.IndexOf('function Test-CoreControlLog(')
$parserEnd = $sourceText.IndexOf('function Invoke-ReadTool(', $parserStart)
Invoke-Expression $sourceText.Substring($parserStart, $parserEnd - $parserStart)
$speedInfo = 'Info : Unable to match requested speed 2000 kHz, using 1800 kHz'
Assert (Test-CoreControlLog 'OPENOCD' 'reset' "$speedInfo`nFLASH_CORE_STATE running") 'OpenOCD speed fallback is not an operation failure'
foreach ($failure in @('Error: unable to reset', 'Info : Unable to match requested speed 2000 kHz', "$speedInfo ERROR", 'Info : Unable to read memory')) {
    Assert (-not (Test-CoreControlLog 'OPENOCD' 'reset' "$speedInfo`n$failure`nFLASH_CORE_STATE running")) 'Real errors must not be filtered'
}
Assert (-not (Test-CoreControlLog 'OPENOCD' 'reset' $speedInfo)) 'Speed fallback alone is not success'
$helper = @'
using System;
using System.IO;
using System.Text.RegularExpressions;
public static class Tool {
    public static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("FLASH_CORE_ROOT");
        string mode = Environment.GetEnvironmentVariable("FLASH_CORE_MODE");
        string command = Environment.GetEnvironmentVariable("FLASH_CORE_COMMAND");
        string text = String.Join(" ", args), state = command == "halt" ? "halted" : "running";
        int file = Array.IndexOf(args, "-CommandFile");
        string kind = file >= 0 ? "jlink" : text.Contains("HOTPLUG") ? "cube" : "openocd";
        if (file >= 0) text = File.ReadAllText(args[file+1]).Replace("\r", "");
        File.AppendAllText(Path.Combine(root, "calls.txt"), String.Join(" ", args) + "\n" + text + "\nCALL_END\n");
        string expected;
        if (kind == "jlink") {
            expected = "EoE 1\nconnect\n" + (command == "halt" ? "h" : command == "go" ? "g" : "r\ng") + "\nIsHalted\nq";
            if (text.Trim() != expected) return 91;
        } else if (kind == "cube") {
            if (command == "go" || !text.Contains("port=SWD") || !text.EndsWith((command == "halt" ? "-halt" : "-rst") + " -score")) return 92;
            if (Regex.IsMatch(text, @"(?:^|\s)-(?:w|e|g|s|u|ob|rdu)(?:\s|$)")) return 93;
        } else {
            expected = "init; " + (command == "halt" ? "halt" : command == "go" ? "resume" : "reset run") + "; poll; echo [format {FLASH_CORE_STATE %s} [[target current] curstate]]; shutdown";
            if (args[args.Length-1] != expected) return 94;
        }
        if (mode == "error") { Console.WriteLine("Error: command failed"); return 7; }
        if (mode == "stale") { Console.WriteLine("No probe found for serial"); return 1; }
        if (mode == "wrong-state") state = command == "halt" ? "running" : "halted";
        if (kind == "jlink") { Console.WriteLine("CPU is halted."); Console.WriteLine("J-Link>IsHalted"); }
        if (mode != "no-state") Console.WriteLine((kind == "jlink" ? "CPU is " : kind == "cube" ? "Core is " : "FLASH_CORE_STATE ") + (kind == "jlink" && state == "running" ? "not halted" : state));
        if (mode == "log-error") Console.WriteLine("Error: operation failed despite state response");
        return 0;
    }
}
'@
$mocks = @'
function Find-CubeProgrammerCli { Join-Path $env:FLASH_CORE_ROOT 'cube.exe' }
function Find-JLinkExe { Join-Path $env:FLASH_CORE_ROOT 'JLink.exe' }
function Find-OpenOcdInstallation { @{Exe=(Join-Path $env:FLASH_CORE_ROOT 'openocd.exe'); Scripts=(Join-Path $env:FLASH_CORE_ROOT 'scripts')} }
function Get-StInfoProbeInfo { throw 'UNEXPECTED_TARGET_DISCOVERY' }
function Find-StInfoExe { throw 'UNEXPECTED_ST_INFO' }
function Get-InfoStLinkInventory {
    if ($env:FLASH_CORE_MODE -eq 'dry') { throw 'UNEXPECTED_INVENTORY' }
    $entries = @([pscustomobject]@{Type='STLINK';Serial='111111111111111111111111';Family='fixture'})
    if ($env:FLASH_CORE_MODE -ne 'single') { $entries += [pscustomobject]@{Type='STLINK';Serial='222222222222222222222222';Family='fixture'} }
    @{Entries=$entries;Warning=$false}
}
function Get-JLinkProbes {
    if ($env:FLASH_CORE_MODE -eq 'dry') { throw 'UNEXPECTED_INVENTORY' }
    [pscustomobject]@{Type='JLINK';Serial='12345678';Family='fixture'}
    if ($env:FLASH_CORE_MODE -ne 'single') { [pscustomobject]@{Type='JLINK';Serial='87654321';Family='fixture'} }
}
function Get-CimInstance { if ($env:FLASH_CORE_MODE -eq 'dry') { throw 'UNEXPECTED_CIM' }; $null }
function Get-WmiObject { if ($env:FLASH_CORE_MODE -eq 'dry') { throw 'UNEXPECTED_WMI' }; $null }
function Read-Host { if ($env:FLASH_CORE_MODE -eq 'multiple') { return '2' }; throw 'UNEXPECTED_PROMPT' }
function Invoke-Item { Add-Content (Join-Path $env:FLASH_CORE_ROOT 'browser.txt') 'open' }
function Invoke-Download { throw 'UNEXPECTED_DOWNLOAD' }
function Invoke-WebRequest { throw 'UNEXPECTED_NETWORK' }
'@
try {
    New-Item -ItemType Directory $root | Out-Null
    $cs = Join-Path $root 'tool.cs'; $exe = Join-Path $root 'cube.exe'
    Set-Content $cs $helper -Encoding ASCII
    & powershell.exe -NoProfile -Command "Add-Type -Path '$cs' -OutputAssembly '$exe' -OutputType ConsoleApplication"
    Assert ($LASTEXITCODE -eq 0) 'Stub compile failed'
    foreach ($name in @('JLink.exe','openocd.exe')) { Copy-Item $exe (Join-Path $root $name) }
    New-Item -ItemType Directory (Join-Path $root 'scripts/target') -Force | Out-Null
    Set-Content (Join-Path $root 'scripts/target/stm32f1x.cfg') '# fixture'
    $source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $position = $source.IndexOf('$CurrentDir     ='); Assert ($position -gt 0) 'Mock boundary'
    $source = $source.Insert($position,$mocks+"`n")
    $source = $source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"'+$PowerShellExe+'" -NoProfile')
    $bin = Join-Path $root 'tool bin'; New-Item -ItemType Directory $bin | Out-Null
    [IO.File]::WriteAllText((Join-Path $bin 'flash.cmd'),$source,(New-Object Text.UTF8Encoding($false)))
    foreach ($command in @('halt','go','reset')) { Copy-Item (Join-Path $repo "bin/$command.cmd") $bin }
    $env:FLASH_CORE_ROOT = $root
    foreach ($engine in @('CUBEPROGRAMMER','CUBE-JLINK','OPENOCD','JLINK')) {
      foreach ($command in @('halt','go','reset')) {
        $supported = $engine -ne 'CUBE-JLINK' -and -not ($engine -eq 'CUBEPROGRAMMER' -and $command -eq 'go')
        $cases = if ($supported) { @('ok','nohex','error','no-state','wrong-state','log-error','stale','explicit','multiple','single','dry','conflict','hex-option','missing-target') } else { @('ok','dry') }
        foreach ($case in $cases) {
            $env:FLASH_CORE_MODE = $case; $env:FLASH_CORE_COMMAND = $command
            $work = Join-Path $root "$engine $command $case"; New-Item -ItemType Directory $work | Out-Null
            # Invalid firmware must be ignored, and its bytes must remain unchanged.
            $hex = Join-Path $work 'unrelated.hex'; Set-Content $hex 'not Intel HEX' -Encoding ASCII
            $hash = (Get-FileHash $hex).Hash
            if ($case -eq 'nohex') { Remove-Item -LiteralPath $hex }
            foreach ($name in @('calls.txt','browser.txt')) { Remove-Item (Join-Path $root $name) -ErrorAction SilentlyContinue }
            $probe = if ($engine -in @('JLINK','CUBE-JLINK')) { 'JLINK' } else { 'STLINK' }
            $serial = if ($probe -eq 'JLINK') { '12345678' } else { '111111111111111111111111' }
            $settings = @{schemaVersion=1;engine=$(if ($engine -eq 'CUBE-JLINK') {'CUBEPROGRAMMER'} else {$engine});probe=$probe;stlinkSerial=$null;jlinkSerial=$null;jlinkDevice='STM32F103CB';openocdTarget='target/stm32f1x.cfg'}
            if ($case -notin @('multiple','single')) { $settings[$(if ($probe -eq 'JLINK') {'jlinkSerial'} else {'stlinkSerial'})] = $serial }
            if ($case -eq 'missing-target') { $settings.openocdTarget = $null; $settings.jlinkDevice = $null }
            $config = Join-Path $work '.flash.json'; $settings | ConvertTo-Json | Set-Content $config -Encoding UTF8
            $before = (Get-FileHash $config).Hash
            $extra = switch ($case) { 'dry' {'-DryRun'}; 'conflict' {'-Erase'}; 'hex-option' {'-HexFile unrelated.hex'}; 'explicit' {'-Serial 99999999'}; default {''} }
            $lang = if ($case -in @('ok','dry','multiple')) { 'ru' } else { 'en' }
            $entry = Join-Path $bin "$command.cmd"
            Push-Location $work
            try {
                $ErrorActionPreference = 'Continue'
                $output = & $env:ComSpec /d /c "`"$entry`" -Lang $lang $extra" 2>&1 | Out-String
                $code = $LASTEXITCODE
            } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
            $missing = $case -eq 'missing-target' -and $engine -in @('OPENOCD','JLINK')
            $success = $supported -and -not $missing -and $case -in @('ok','nohex','explicit','multiple','single','dry','missing-target')
            Assert ($code -eq $(if ($success) {0} else {1})) "$engine $command $case exit $code : $output"
            Assert ($output -notmatch 'UNEXPECTED_') "$engine $command $case unexpected: $output"
            $called = $supported -and -not $missing -and $case -notin @('dry','conflict','hex-option')
            Assert ((Test-Path (Join-Path $root 'calls.txt')) -eq $called) "$engine $command $case tool invocation"
            if ($called) {
                $calls = Get-Content (Join-Path $root 'calls.txt') -Raw
                Assert (([regex]::Matches($calls,'CALL_END')).Count -eq 1) 'Unexpected retry'
                $wanted = if ($case -eq 'explicit') { '99999999' } elseif ($case -eq 'multiple') { if ($probe -eq 'JLINK') {'87654321'} else {'222222222222222222222222'} } else { $serial }
                if ($case -eq 'single') { Assert ($calls -notmatch 'sn=|-usb') 'Single probe must not require serial' }
                else { Assert ($calls -match [regex]::Escape($wanted)) 'Wrong serial' }
                $sessions = @(Get-ChildItem (Join-Path $work '.history') -Recurse -Filter '*.json' | Where-Object Name -ne 'index.json')
                Assert ($sessions.Count -eq 1) 'Missing history'
                $session = Get-Content $sessions[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                Assert ($session.Operation -eq $command -and $session.Success -eq $success -and -not $session.HexName) 'Wrong history'
                Assert ((Test-Path (Join-Path $root 'browser.txt')) -eq (-not $success)) 'Browser policy'
            }
            if ($case -eq 'dry') {
                Assert ((Get-FileHash $config).Hash -eq $before) 'DryRun changed settings'
                Assert (@(Get-ChildItem $work -Force).Count -eq 2) 'DryRun created files'
            }
            if ($case -eq 'nohex') { Assert (-not (Test-Path $hex)) 'Created HEX' }
            else { Assert ((Get-FileHash $hex).Hash -eq $hash) 'HEX changed' }
            Assert (-not (Test-Path (Join-Path $work 'backups'))) 'Unexpected backup'
            Assert (@(Get-ChildItem $work -Force -Filter '.flash_read_*').Count -eq 0) 'Temporary output leaked'
            Assert (-not (Test-Path (Join-Path $work '.jlink_flash.jlink'))) 'J-Link script leaked'
            Write-Host "$engine $command $case PASS"
        }
      }
    }
} finally {
    $env:FLASH_CORE_ROOT = $oldRoot; $env:FLASH_CORE_MODE = $oldMode; $env:FLASH_CORE_COMMAND = $oldCommand
}
