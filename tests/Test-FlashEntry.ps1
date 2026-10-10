param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-entry-' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:FLASH_ENTRY_ROOT
$oldMode = $env:FLASH_ENTRY_MODE
$oldAnswer = $env:FLASH_ENTRY_ANSWER
New-Item -ItemType Directory $root | Out-Null
$helper = @'
using System;
using System.IO;
public static class Tool {
    public static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("FLASH_ENTRY_ROOT");
        File.AppendAllText(Path.Combine(root, "calls.txt"), "call\n");
        File.WriteAllLines(Path.Combine(root, "args.txt"), args);
        string mode = Environment.GetEnvironmentVariable("FLASH_ENTRY_MODE");
        if (mode.EndsWith("error")) { Console.Error.WriteLine("Fixture write failed"); return 7; }
        if (mode == "missing-marker") { Console.WriteLine("STM32CubeProgrammer v0.0.0\nVoltage : 3.30V\nFile download complete"); return 0; }
        int w = Array.IndexOf(args, "-w");
        int c = Array.IndexOf(args, "-CommandFile");
        if (w >= 0) {
            if (w + 1 >= args.Length || !File.Exists(args[w + 1]) || Array.IndexOf(args,"-v") < 0) return 9;
            Console.WriteLine("STM32CubeProgrammer v0.0.0\nVoltage : 3.30V\nFile download complete\nDownload verified successfully");
        } else if (c >= 0) {
            if (c + 1 >= args.Length || !File.Exists(args[c + 1])) return 9;
            string script = File.ReadAllText(args[c + 1]);
            if (!script.Contains("loadfile \"") || !script.Contains("EoE 1")) return 9;
            Console.WriteLine("SEGGER J-Link Commander V0.00\nDownloading file...O.K.");
        } else if (Array.IndexOf(args, "-f") >= 0 && String.Join(" ", args).Contains("verify reset exit")) {
            Console.WriteLine("Open On-Chip Debugger 0.0\nInfo : target voltage: 3.30\n** Programming Finished **\n** Verified OK **");
        } else { return 9; }
        return 0;
    }
}
'@
$mocks = @'
function Find-CubeProgrammerCli { Join-Path $env:FLASH_ENTRY_ROOT 'cube.exe' }
function Find-JLinkExe { Join-Path $env:FLASH_ENTRY_ROOT 'JLink.exe' }
function Find-StInfoExe { $null }
function Find-OpenOcdInstallation { @{ Exe=(Join-Path $env:FLASH_ENTRY_ROOT 'openocd.exe'); Scripts=(Join-Path $env:FLASH_ENTRY_ROOT 'scripts') } }
function Get-UsbStLinkProbes { @() }
function Get-JLinkProbes { @() }
function Get-InfoStLinkInventory { @{Entries=@(); Warning=$false; Source='fixture'} }
function Get-CimInstance { $null }
function Get-WmiObject { $null }
function Read-Host { if ($env:FLASH_ENTRY_ANSWER) { return $env:FLASH_ENTRY_ANSWER }; throw 'UNEXPECTED_PROMPT' }
function Invoke-Item { Add-Content (Join-Path $env:FLASH_ENTRY_ROOT 'browser.txt') 'open' }
function Invoke-WebRequest { throw 'UNEXPECTED_NETWORK' }
function Invoke-RestMethod { throw 'UNEXPECTED_NETWORK' }
function Invoke-Download { throw 'UNEXPECTED_NETWORK' }
'@
function Assert($ok, $message) { if (-not $ok) { throw $message } }
try {
    $cs = Join-Path $root 'tool.cs'
    Set-Content $cs $helper -Encoding ASCII
    $exe = Join-Path $root 'cube.exe'
    & powershell.exe -NoProfile -Command "Add-Type -Path '$cs' -OutputAssembly '$exe' -OutputType ConsoleApplication"
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path $exe)) 'Stub compilation failed'
    Copy-Item $exe (Join-Path $root 'JLink.exe')
    Copy-Item $exe (Join-Path $root 'openocd.exe')
    New-Item -ItemType Directory (Join-Path $root 'scripts/target') -Force | Out-Null
    Set-Content (Join-Path $root 'scripts/target/stm32f1x.cfg') '# fixture'
    $source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Missing mock boundary'
    $source = $source.Insert($position, $mocks + "`n")
    $source = $source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    $bin = Join-Path $root 'tool bin'
    New-Item -ItemType Directory $bin | Out-Null
    [IO.File]::WriteAllText((Join-Path $bin 'flash.cmd'), $source, (New-Object Text.UTF8Encoding($false)))
    $env:FLASH_ENTRY_ROOT = $root
    foreach ($layout in @('external', 'copied')) {
    foreach ($case in @('fresh', 'saved', 'jlink', 'openocd', 'relative', 'absolute', 'positional', 'nohex', 'multiple', 'error', 'jlink-error', 'openocd-error', 'missing-marker', 'checksum-bad')) {
        $work = Join-Path $root "$layout $case"
        New-Item -ItemType Directory $work | Out-Null
        $entry = Join-Path $bin 'flash.cmd'
        if ($layout -eq 'copied') {
            Copy-Item -LiteralPath $entry -Destination $work
            $entry = Join-Path $work 'flash.cmd'
        }
        $hex = Join-Path $work 'firmware.hex'
        if ($case -ne 'nohex') { Set-Content $hex ":0400000001020304F2`r`n:00000001FF" -Encoding ASCII }
        if ($case -eq 'multiple') { Copy-Item $hex (Join-Path $work 'second.hex') }
        if ($case -ne 'fresh') { Set-Content (Join-Path $work '.flash_engine') $(if ($case -like 'jlink*') { Join-Path $root 'JLink.exe' } elseif ($case -like 'openocd*') { 'OPENOCD' } else { $exe }) }
        if ($case -like 'openocd*') { Set-Content (Join-Path $work '.openocd_target') 'target/stm32f1x.cfg' }
        if ($case -eq 'checksum-bad') { Set-Content "$hex.sha256" ('0' * 64) -Encoding ASCII }
        if ($case -like 'jlink*') {
            Set-Content (Join-Path $work '.probe_type') 'JLINK'
            Set-Content (Join-Path $work '.jlink_device') 'STM32F103CB'
        }
        foreach ($name in @('calls.txt','args.txt','browser.txt')) { Remove-Item (Join-Path $root $name) -ErrorAction SilentlyContinue }
        $env:FLASH_ENTRY_MODE = $case
        $env:FLASH_ENTRY_ANSWER = if ($case -eq 'multiple') { 'invalid' } else { '' }
        $arguments = switch ($case) { relative { '-HexFile .\firmware.hex' }; absolute { '-HexFile "' + $hex + '"' }; positional { '.\firmware.hex' }; default { '' } }
        Push-Location $work
        try {
            $output = & $env:ComSpec /d /c "`"$entry`" $arguments" 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { Pop-Location }
        $success = $case -notin @('nohex','multiple','error','jlink-error','openocd-error','missing-marker','checksum-bad')
        Assert ($code -eq $(if ($success) { 0 } else { 1 })) "$case exit $code : $output"
        Assert ($output.Trim().Length -gt 0) "$case silent exit"
        Assert ($output -notmatch 'UNEXPECTED_') "$case unexpected boundary: $output"
        if ($case -in @('nohex','multiple','checksum-bad')) {
            Assert (-not (Test-Path (Join-Path $root 'calls.txt'))) "$case called engine"
        } else {
            Assert ((Test-Path (Join-Path $root 'calls.txt'))) "$case did not call real stub EXE"
            Assert (Test-Path (Join-Path $work '.flash.json')) "$case missing unified configuration"
            Assert (@(Get-ChildItem -LiteralPath $work -Force -File | Where-Object Name -in @('.flash_engine','.probe_type','.stlink_serial','.jlink_serial','.jlink_device','.openocd_target')).Count -eq 0) "$case recreated legacy settings"
            Assert (@(Get-Content (Join-Path $root 'calls.txt')).Count -eq 1) "$case duplicate engine call"
            Assert (Test-Path (Join-Path $work 'report.html')) "$case missing report"
            $json = @(Get-ChildItem (Join-Path $work '.history') -Filter '*.json' -Recurse | Where-Object Name -ne 'index.json')
            Assert ($json.Count -eq 1) "$case missing session"
            $session = Get-Content $json[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert ($session.Success -eq $success) "$case incorrect success"
            Assert ((Test-Path (Join-Path $root 'browser.txt')) -eq (-not $success)) "$case browser policy"
        }
        Assert (@(Get-ChildItem -LiteralPath $bin -Force).Count -eq 1) "$layout $case wrote artifacts beside external script"
        Write-Host "$layout $case PASS (real CMD and stub EXE)"
    }
    }
} finally {
    $env:FLASH_ENTRY_ROOT = $oldRoot; $env:FLASH_ENTRY_MODE = $oldMode; $env:FLASH_ENTRY_ANSWER = $oldAnswer
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($root))) -ne $PSScriptRoot) { throw 'Invalid fixture root' }
    Remove-Item -LiteralPath $root -Recurse -Force
}
