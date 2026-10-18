param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path $PSScriptRoot ('.tmp-doctor-' + [guid]::NewGuid().ToString('N'))
$oldRoot=$env:DOCTOR_TEST_ROOT; $oldMode=$env:DOCTOR_TEST_MODE
function Assert($ok,$message) { if (-not $ok) { throw $message } }
$helper=@'
using System;
using System.IO;
using System.Threading;
public static class DoctorTool {
    public static int Main(string[] args) {
        string root=Environment.GetEnvironmentVariable("DOCTOR_TEST_ROOT");
        string mode=Environment.GetEnvironmentVariable("DOCTOR_TEST_MODE");
        string line=String.Join(" ",args);
        File.AppendAllText(Path.Combine(root,"calls.txt"),line+"\n");
        if (mode=="timeout") { Thread.Sleep(10000); return 0; }
        if (line=="--version") {
            if (mode=="unknown") { Console.WriteLine("unknown format"); return 0; }
            if (mode=="failed") return 2;
            if (System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName.EndsWith("openocd.exe")) {
                Console.WriteLine("Open On-Chip Debugger 0.12.0 (fixture-build)"); return 0;
            }
            Console.WriteLine("STM32CubeProgrammer v2.19.0"); return 0;
        }
        if (line=="--help") { Console.WriteLine(mode=="old-cli" ? "-l st" : "-l <stlink-only>"); return 0; }
        if (line=="-l stlink-only") {
            if (mode=="inventory-timeout") { Thread.Sleep(10000); return 0; }
            if (mode=="inventory-error") return 3;
            if (mode=="empty") { Console.WriteLine("No ST-LINK probe found"); return 0; }
            if (mode=="empty-error") { Console.WriteLine("Error: USB failed\nNo ST-LINK probe found"); return 0; }
            if (mode=="garbled") { Console.WriteLine("unrecognized response"); return 0; }
            Console.WriteLine("-------- Connected ST-LINK Probes List --------");
            Console.WriteLine("ST-Link Probe 0 :\n   ST-LINK SN : " + (mode=="unknown-serial" ? "not-a-serial" : "00112233445566778899AABB"));
            if (mode=="multiple") Console.WriteLine("ST-Link Probe 1 :\n   ST-LINK SN : 112233445566778899AABBCC");
            if (mode=="partial") Console.WriteLine("ST-Link Probe 1 :\n   incomplete");
            Console.WriteLine("-----------------------------------------------"); return 0;
        }
        if (line=="-nogui 1") {
            string input=Console.In.ReadToEnd();
            File.AppendAllText(Path.Combine(root,"calls.txt"),input+"\n");
            if (input.Trim()!="q" && input.Trim()!="ShowEmuList USB\nq" && input.Trim()!="ShowEmuList USB\r\nq") return 99;
            Console.WriteLine("SEGGER J-Link Commander V8.32");
            if (mode=="windows-only") Console.WriteLine("Connecting to J-Link via USB...FAILED: Cannot connect to J-Link.");
            if (input.Contains("ShowEmuList") && mode!="garbled" && mode!="windows-only") Console.WriteLine("J-Link[0]: Connection: USB, Serial number: 12345678, ProductName: Fixture");
            return 0;
        }
        File.WriteAllText(Path.Combine(root,"FORBIDDEN"),line); return 99;
    }
}
'@
$mocks=@'
function Get-DoctorRuntime { 'Supported' }
function Test-WindowsJLinkPresent { $env:DOCTOR_TEST_MODE -eq 'windows-only' }
function Find-CubeProgrammerCli { Join-Path $env:DOCTOR_TEST_ROOT 'bin/STM32_Programmer_CLI.exe' }
function Find-JLinkExe { Join-Path $env:DOCTOR_TEST_ROOT 'bin/JLink.exe' }
function Find-OpenOcdInstallation { @{Exe=(Join-Path $env:DOCTOR_TEST_ROOT 'bin/openocd.exe'); Scripts=(Join-Path $env:DOCTOR_TEST_ROOT 'scripts')} }
function Find-StInfoExe { $null }
function Read-Host { throw 'FORBIDDEN_PROMPT' }
function Enter-DirectoryLock { throw 'FORBIDDEN_LOCK' }
function Write-LaunchConfiguration { throw 'FORBIDDEN_WRITE' }
function Get-CimInstance { throw 'FORBIDDEN_USB' }
function Get-JLinkProbes { throw 'FORBIDDEN_DISCOVERY' }
function Get-UsbStLinkProbes { throw 'FORBIDDEN_DISCOVERY' }
function Invoke-WebRequest { throw 'FORBIDDEN_NETWORK' }
function Invoke-Download { throw 'FORBIDDEN_DOWNLOAD' }
'@
try {
    New-Item -ItemType Directory (Join-Path $root 'bin') -Force | Out-Null
    $cs=Join-Path $root 'tool.cs'; Set-Content $cs $helper -Encoding ASCII
    $exe=Join-Path $root 'bin/STM32_Programmer_CLI.exe'
    & powershell.exe -NoProfile -Command "Add-Type -Path '$cs' -OutputAssembly '$exe' -OutputType ConsoleApplication"
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path $exe)) 'Stub compilation failed'
    Copy-Item $exe (Join-Path $root 'bin/JLink.exe')
    Copy-Item $exe (Join-Path $root 'bin/openocd.exe')
    New-Item -ItemType Directory (Join-Path $root 'scripts/interface') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $root 'scripts/target') -Force | Out-Null
    Set-Content (Join-Path $root 'scripts/interface/stlink.cfg') '# fixture'
    Set-Content (Join-Path $root 'scripts/target/stm32f1x.cfg') '# fixture'
    $source=Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert (-not $errors.Count) 'Invalid source syntax'
    $runtimeNode=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DoctorRuntime'},$true)
    . ([scriptblock]::Create($runtimeNode.Extent.Text))
    function Get-ItemProperty { if ($script:testProduct -eq 'failure') { throw 'fixture' }; @{ProductType=$script:testProduct} }
    try {
        foreach ($product in @('WinNT','ServerNT','LanmanNT','unknown','failure')) {
            $script:testProduct=$product
            $expectedRuntime=switch ($product) { 'WinNT' {'Supported'} { $_ -in @('ServerNT','LanmanNT') } {'Unsupported'} default {'Unknown'} }
            Assert ((Get-DoctorRuntime) -eq $expectedRuntime) "Runtime classification: $product"
        }
    } finally { Remove-Item Function:Get-ItemProperty }
    $position=$source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Missing fixture boundary'
    $source=$source.Insert($position,$mocks + "`n")
    $source=$source.Replace('[int]$timeoutMs = 10000','[int]$timeoutMs = 1000')
    $source=$source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $root 'flash.cmd'),$source,(New-Object Text.UTF8Encoding($false)))
    Copy-Item (Join-Path $repo 'bin/doctor.cmd') $root
    $env:DOCTOR_TEST_ROOT=$root
    foreach ($case in @('normal','copied','legacy','invalid','help','version','dry','conflict','hex','probe-target','badprobe','badengine','missing','unstartable','unknown','failed','timeout','inventory-timeout','inventory-error','empty','empty-error','garbled','unknown-serial','multiple','partial','old-cli','serial-missing','override','jlink','target','target-missing','auto','unsupported','windows-only')) {
      foreach ($lang in @('ru','en')) {
        $work=Join-Path $root "$case-$lang"
        New-Item -ItemType Directory $work | Out-Null
        $config=[ordered]@{schemaVersion=1; engine='CUBEPROGRAMMER'; probe='STLINK'}
        $arguments="-Lang $lang"; $expected=0
        $env:DOCTOR_TEST_MODE=$case
        switch ($case) {
            'invalid' { $expected=1 }
            'help' { $arguments+=' --help' }
            'version' { $arguments+=' --version' }
            'dry' { $arguments+=' -DryRun' }
            'conflict' { $arguments+=' -Erase'; $expected=1 }
            'hex' { $arguments+=' -HexFile firmware.hex'; $expected=1 }
            'probe-target' { $arguments+=' -ProbeTarget'; $expected=1 }
            'badprobe' { $arguments+=' -Probe invalid'; $expected=1 }
            'badengine' { $arguments+=' -Engine invalid'; $expected=1 }
            'missing' { $config.engine=Join-Path $work 'STM32_Programmer_CLI.exe'; $expected=1 }
            'unstartable' { $config.engine=Join-Path $work 'STM32_Programmer_CLI.exe'; Set-Content $config.engine 'not an executable'; $expected=1 }
            'empty' { $expected=1 }
            'serial-missing' { $arguments+=' -Serial absent'; $expected=1 }
            'unknown-serial' { $arguments+=' -Serial absent' }
            'override' { $config.engine=Join-Path $work 'STM32_Programmer_CLI.exe'; $arguments+=' -Engine JLINK -Probe JLINK -Device STM32F103CB' }
            'jlink' { $config.engine='JLINK'; $config.probe='JLINK'; $arguments+=' -Serial 12345678 -Device STM32F103CB' }
            'target' { $config.engine='OPENOCD'; $arguments+=' -Target target/stm32f1x.cfg' }
            'target-missing' { $config.engine='OPENOCD'; $arguments+=' -Target target/missing.cfg'; $expected=1 }
            'auto' { $config=[ordered]@{schemaVersion=1} }
            'unsupported' { $config.engine='JLINK'; $config.probe='STLINK'; $expected=1 }
            'windows-only' { $config.engine='JLINK'; $config.probe='JLINK' }
        }
        if ($case -in @('invalid','help','version','dry')) { Set-Content (Join-Path $work '.flash.json') '{invalid' }
        elseif ($case -eq 'legacy') {
            Set-Content (Join-Path $work '.flash_engine') 'CUBEPROGRAMMER'
            Set-Content (Join-Path $work '.probe_type') 'STLINK'
        } else { $config | ConvertTo-Json | Set-Content (Join-Path $work '.flash.json') }
        $entry=Join-Path $root 'doctor.cmd'
        if ($case -eq 'copied') {
            Copy-Item (Join-Path $root 'flash.cmd') $work
            Copy-Item $entry $work
            $entry=Join-Path $work 'doctor.cmd'
        }
        $before=Get-ChildItem $work -Force -Recurse | Get-FileHash | ConvertTo-Json
        $calls=Join-Path $root 'calls.txt'; Remove-Item $calls -ErrorAction SilentlyContinue
        Push-Location $work
        try { $output=& $env:ComSpec /d /c "`"$entry`" $arguments" 2>&1 | Out-String; $code=$LASTEXITCODE }
        finally { Pop-Location }
        Assert ($code -eq $expected) "$case/$lang exit $code expected $expected : $output"
        Assert ($output -notmatch 'FORBIDDEN|Doctor[A-Z]') "$case/$lang unsafe call or untranslated key: $output"
        Assert (($output -match 'Zadig') -eq ($case -eq 'windows-only')) "Incorrect Windows-only warning: $output"
        if ($case -ne 'version') { Assert (($output -match '[\u0400-\u04ff]') -eq ($lang -eq 'ru')) "Wrong locale: $output" }
        $after=Get-ChildItem $work -Force -Recurse | Get-FileHash | ConvertTo-Json
        Assert ($before -ceq $after) "$case/$lang changed working files"
        Assert (-not (Test-Path (Join-Path $root 'FORBIDDEN'))) 'Non-reference tool operation'
        if ($case -in @('invalid','help','version','dry','conflict','hex','probe-target','badprobe','badengine')) { Assert (-not (Test-Path $calls)) "$case queried tools" }
        if ($case -in @('normal','jlink','override','legacy')) { Assert ($output -match '\[OK\]' -and $output -notmatch '\[ERROR\]') "Missing success findings: $output" }
        if ($case -in @('timeout','inventory-timeout','inventory-error','empty-error','garbled','unknown-serial','multiple','partial','old-cli','unknown','failed','auto')) { Assert ($output -match '\[WARN\]') "Missing warning: $output" }
        if ($case -eq 'normal' -and $lang -eq 'en') { Assert ($output -match 'Version matches') "Version not parsed: $output" }
        if ($case -eq 'old-cli') { Assert ((Get-Content $calls -Raw) -notmatch '-l ') 'Unsafe old Cube inventory' }
      }
      Write-Host "Doctor $case RU/EN PASS"
    }
} finally {
    $env:DOCTOR_TEST_ROOT=$oldRoot; $env:DOCTOR_TEST_MODE=$oldMode
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($root))) -ne $PSScriptRoot) { throw 'Invalid fixture path' }
    Remove-Item -LiteralPath $root -Recurse -Force
}
