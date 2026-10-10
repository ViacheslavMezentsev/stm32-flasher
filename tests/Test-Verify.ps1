param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-verify-' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:FLASH_VERIFY_ROOT; $oldMode = $env:FLASH_VERIFY_MODE
$oldEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Record([int]$type, [int]$offset, [byte[]]$data) {
    $bytes = @($data.Count, ($offset -shr 8), ($offset -band 255), $type) + @($data)
    $sum = ($bytes | Measure-Object -Sum).Sum
    ':' + (($bytes + @((256 - ($sum % 256)) % 256) | ForEach-Object { '{0:X2}' -f [int]$_ }) -join '')
}
$helper = @'
using System;
using System.IO;
using System.Text.RegularExpressions;
public static class Tool {
    public static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("FLASH_VERIFY_ROOT");
        string mode = Environment.GetEnvironmentVariable("FLASH_VERIFY_MODE");
        string text = String.Join(" ", args), file = null, marker = null;
        long address = 0; int size = 0;
        int c = Array.IndexOf(args, "-CommandFile"), u = Array.IndexOf(args, "-u");
        if (c >= 0) {
            text = File.ReadAllText(args[c + 1]);
            Match m = Regex.Match(text, "savebin \"([^\"]+)\" 0x([0-9A-F]+) 0x([0-9A-F]+)");
            if (!m.Success) return 91;
            file = m.Groups[1].Value; address = Convert.ToInt64(m.Groups[2].Value,16); size = Convert.ToInt32(m.Groups[3].Value,16);
            marker = "Reading " + size + " bytes from addr 0x08000000...O.K.";
        } else if (u >= 0) {
            address = Convert.ToInt64(args[u+1].Substring(2),16); size = Int32.Parse(args[u+2]); file = args[u+3];
            marker = "Data read successfully";
        } else {
            Match m = Regex.Match(text, @"dump_image \{([^}]+)\} 0x([0-9A-F]+) (\d+)");
            if (!m.Success) return 92;
            file = m.Groups[1].Value; address = Convert.ToInt64(m.Groups[2].Value,16); size = Int32.Parse(m.Groups[3].Value);
            marker = "FLASH_BACKUP_COMPLETE";
        }
        File.AppendAllText(Path.Combine(root,"calls.txt"), (c >= 0 ? String.Join(" ",args) + "\n" : "") + text + "\n");
        if (Regex.IsMatch(text, @"(?im)(\bprogram\b|\bloadfile\b|\berase\b|\breset\b|\bresume\b|^r\s*$|^g\s*$|(?:^|\s)-(?:w|e|rst|g)(?:\s|$))")) return 93;
        if (mode == "error") { Console.WriteLine("Error: read failed"); return 7; }
        if (mode == "stale") { Console.WriteLine("No J-Link probe found for serial"); return 1; }
        byte[] data = new byte[size];
        for (int i=0; i<size; i++) data[i] = (byte)(address - 0x08000000 + i + 1);
        if (mode == "mismatch" || (mode == "late-mismatch" && address == 0x08000008)) data[0] ^= 1;
        if (mode == "short") Array.Resize(ref data, size-1);
        if (mode != "missing-file") File.WriteAllBytes(file,data);
        if (mode != "missing-marker") Console.WriteLine(marker);
        return 0;
    }
}
'@
$mocks = @'
function Find-CubeProgrammerCli { Join-Path $env:FLASH_VERIFY_ROOT 'cube.exe' }
function Find-JLinkExe { Join-Path $env:FLASH_VERIFY_ROOT 'JLink.exe' }
function Find-OpenOcdInstallation { @{Exe=(Join-Path $env:FLASH_VERIFY_ROOT 'openocd.exe'); Scripts=(Join-Path $env:FLASH_VERIFY_ROOT 'scripts')} }
function Get-StInfoProbeInfo { throw 'UNEXPECTED_TARGET_DISCOVERY' }
function Find-StInfoExe { throw 'UNEXPECTED_ST_INFO' }
function Get-InfoStLinkInventory { if ($env:FLASH_VERIFY_MODE -eq 'dry') { throw 'UNEXPECTED_INVENTORY' }; @{Entries=@([pscustomobject]@{Type='STLINK';Serial='111111111111111111111111';Family='fixture'},[pscustomobject]@{Type='STLINK';Serial='222222222222222222222222';Family='fixture'});Warning=$false} }
function Get-JLinkProbes { if ($env:FLASH_VERIFY_MODE -eq 'dry') { throw 'UNEXPECTED_INVENTORY' }; @([pscustomobject]@{Type='JLINK';Serial='12345678';Family='fixture'},[pscustomobject]@{Type='JLINK';Serial='87654321';Family='fixture'}) }
function Get-CimInstance { if ($env:FLASH_VERIFY_MODE -eq 'dry') { throw 'UNEXPECTED_CIM' }; $null }
function Get-WmiObject { if ($env:FLASH_VERIFY_MODE -eq 'dry') { throw 'UNEXPECTED_WMI' }; $null }
function Read-Host { if ($env:FLASH_VERIFY_MODE -eq 'multiple') { return '2' }; throw 'UNEXPECTED_PROMPT' }
function Invoke-Item { Add-Content (Join-Path $env:FLASH_VERIFY_ROOT 'browser.txt') 'open' }
function Invoke-Download { throw 'UNEXPECTED_DOWNLOAD' }
function Invoke-WebRequest { throw 'UNEXPECTED_NETWORK' }
'@
try {
    New-Item -ItemType Directory $root | Out-Null
    $source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $errors=$null; $tokens=$null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert (-not $errors.Count) "Syntax: $errors"
    foreach ($name in @('Test-PreviewHex','Read-VerifyRanges')) {
        $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $hexLines = @((Record 4 0 @(8,0)), (Record 0 0 @(1,2,3,4)), (Record 0 4 @(5,6)), (Record 0 8 @(9,10)), ':00000001FF')
    $sample = Join-Path $root 'sample.hex'
    Set-Content $sample $hexLines -Encoding ASCII
    $ranges = @(Read-VerifyRanges $sample)
    Assert ($ranges.Count -eq 2 -and $ranges[0].Bytes.Count -eq 6 -and $ranges[1].Address -eq 134217736) 'Sparse/contiguous ranges'
    Set-Content $sample @((Record 2 0 @(16,0)),(Record 0 2 @(1,2)),':00000001FF') -Encoding ASCII
    Assert ((@(Read-VerifyRanges $sample))[0].Address -eq 65538) 'Segment address'
    foreach ($bad in @('overlap','overflow')) {
        $lines = if ($bad -eq 'overlap') { @((Record 0 0 @(1,2)),(Record 0 1 @(2)),':00000001FF') } else { @((Record 4 0 @(255,255)),(Record 0 65535 @(1,2)),':00000001FF') }
        Set-Content $sample $lines -Encoding ASCII
        $failed=$false
        try { $null=@(Read-VerifyRanges $sample) } catch { $failed=$true }
        Assert $failed "$bad accepted"
    }
    $cs=Join-Path $root 'tool.cs'; $exe=Join-Path $root 'cube.exe'
    Set-Content $cs $helper -Encoding ASCII
    & powershell.exe -NoProfile -Command "Add-Type -Path '$cs' -OutputAssembly '$exe' -OutputType ConsoleApplication"
    Assert ($LASTEXITCODE -eq 0) 'Stub compile'
    Copy-Item $exe (Join-Path $root 'JLink.exe'); Copy-Item $exe (Join-Path $root 'openocd.exe')
    New-Item -ItemType Directory (Join-Path $root 'scripts/target') -Force | Out-Null
    Set-Content (Join-Path $root 'scripts/target/stm32f1x.cfg') '# fixture'
    $position=$source.IndexOf('$CurrentDir     ='); Assert ($position -gt 0) 'Mock boundary'
    $source=$source.Insert($position,$mocks+"`n")
    $source=$source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"'+$PowerShellExe+'" -NoProfile')
    $bin=Join-Path $root 'tool bin'; New-Item -ItemType Directory $bin | Out-Null
    [IO.File]::WriteAllText((Join-Path $bin 'flash.cmd'),$source,(New-Object Text.UTF8Encoding($false)))
    Copy-Item (Join-Path $repo 'bin/verify.cmd') $bin
    $env:FLASH_VERIFY_ROOT=$root
    foreach ($engine in @('CUBEPROGRAMMER','CUBE-JLINK','OPENOCD','JLINK')) {
      foreach ($case in @('ok','mismatch','late-mismatch','short','missing-file','missing-marker','error','stale','multiple','explicit','dry','badhex','badhash','hash-mismatch','badpath','badprobe','unsupported','conflict')) {
        $env:FLASH_VERIFY_MODE=$case
        $work=Join-Path $root "$engine $case"; New-Item -ItemType Directory $work | Out-Null
        $hex=Join-Path $work 'firmware image.hex'
        Set-Content $hex $hexLines -Encoding ASCII
        if ($case -eq 'badhex') { Set-Content $hex ':00000001FE' -Encoding ASCII }
        if ($case -eq 'badhash') { Set-Content "$hex.sha256" 'invalid checksum' -Encoding ASCII }
        if ($case -eq 'hash-mismatch') { Set-Content "$hex.sha256" ('0' * 64) -Encoding ASCII }
        $hexHash = (Get-FileHash $hex).Hash
        foreach ($name in @('calls.txt','browser.txt')) { Remove-Item (Join-Path $root $name) -ErrorAction SilentlyContinue }
        $probeType=if ($engine -in @('JLINK','CUBE-JLINK')) {'JLINK'} else {'STLINK'}
        $serial=if ($probeType -eq 'JLINK') {'12345678'} else {'111111111111111111111111'}
        $settings=@{schemaVersion=1;engine=$(if ($engine -eq 'CUBE-JLINK') {'CUBEPROGRAMMER'} else {$engine});probe=$probeType;stlinkSerial=$null;jlinkSerial=$null;jlinkDevice='STM32F103CB';openocdTarget='target/stm32f1x.cfg'}
        if ($case -ne 'multiple') { $settings[$(if ($probeType -eq 'JLINK') {'jlinkSerial'} else {'stlinkSerial'})]=$serial }
        $config=Join-Path $work '.flash.json'; $settings | ConvertTo-Json | Set-Content $config -Encoding UTF8
        $before=(Get-FileHash $config).Hash
        $extra=switch ($case) {
            'dry' {'-DryRun'}; 'conflict' {'-Erase'}; 'badpath' {'-HexFile missing.hex'}
            'badprobe' {'-Probe invalid'}; 'unsupported' {'-Command invalid'}
            'explicit' {'-Serial 99999999'}; default {''}
        }
        $lang=if ($case -in @('ok','mismatch','dry')) {'ru'} else {'en'}
        $entry = Join-Path $bin $(if ($case -eq 'unsupported') {'flash.cmd'} else {'verify.cmd'})
        Push-Location $work
        try {
            # PS5.1 wraps native stderr; the child exit code is the assertion target.
            $ErrorActionPreference='Continue'
            $output=& $env:ComSpec /d /c "`"$entry`" -Lang $lang $extra" 2>&1 | Out-String
            $code=$LASTEXITCODE
        } finally { $ErrorActionPreference='Stop'; Pop-Location }
        $success=$case -in @('ok','multiple','explicit','dry')
        Assert ($code -eq $(if ($success) {0} else {1})) "$engine $case exit $code : $output"
        Assert ($output -notmatch 'UNEXPECTED_') "$engine $case unexpected: $output"
        if ($case -in @('dry','badhex','badhash','hash-mismatch','badpath','badprobe','unsupported','conflict')) {
            Assert (-not (Test-Path (Join-Path $root 'calls.txt'))) "$case called engine"
            if ($case -eq 'dry') { Assert ((Get-FileHash $config).Hash -eq $before) 'DryRun wrote config' }
        } else {
            $calls=Get-Content (Join-Path $root 'calls.txt') -Raw
            Assert ($calls -notmatch '(?im)(\bprogram\b|\bloadfile\b|\berase\b|\breset\b|\bresume\b|^r\s*$|^g\s*$)') 'Destructive command'
            if ($case -eq 'multiple') { Assert ($calls -match $(if ($probeType -eq 'JLINK') {'87654321'} else {'222222222222222222222222'})) 'Wrong selected probe' }
            if ($case -eq 'multiple') {
                $saved=Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json
                Assert ($(if ($probeType -eq 'JLINK') {$saved.jlinkSerial -eq '87654321'} else {$saved.stlinkSerial -eq '222222222222222222222222'})) 'Selected probe not saved'
            }
            if ($engine -like 'CUBE*') { Assert ($calls -match $(if ($probeType -eq 'JLINK') {'port=JLINK'} else {'port=SWD'})) 'Wrong Cube connection port' }
            if ($case -eq 'explicit') { Assert ($calls -match '99999999' -and $calls -notmatch [regex]::Escape($serial)) 'CLI serial not preserved' }
            if ($case -eq 'stale') { Assert (([regex]::Matches($calls,'savebin|dump_image| -u ')).Count -eq 1) 'Retried stale serial' }
            $sessions=@(Get-ChildItem (Join-Path $work '.history') -Recurse -Filter '*.json' | Where-Object Name -ne 'index.json')
            Assert ($sessions.Count -eq 1) 'Missing history'
            $session=Get-Content $sessions[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert ($session.Operation -eq 'verify' -and $session.Success -eq $success) 'Wrong history status'
            Assert ((Test-Path (Join-Path $root 'browser.txt')) -eq (-not $success)) 'Browser policy'
            if ($case -eq 'mismatch') { Assert ((Get-Content (Join-Path $work 'flash_log.txt') -Raw -Encoding UTF8) -match '0x08000000') 'Missing mismatch address' }
            if ($case -eq 'late-mismatch') { Assert ((Get-Content (Join-Path $work 'flash_log.txt') -Raw -Encoding UTF8) -match '0x08000008') 'Missing second range mismatch address' }
        }
        Assert ((Get-FileHash $hex).Hash -eq $hexHash) 'Input HEX changed'
        Assert (@(Get-ChildItem $work -Force -Filter '.flash_read_*').Count -eq 0) 'Read artifacts leaked'
        Assert (-not (Test-Path (Join-Path $work 'backups'))) 'Verify created backup'
        Write-Host "$engine $case PASS"
      }
    }
} finally {
    $env:FLASH_VERIFY_ROOT=$oldRoot; $env:FLASH_VERIFY_MODE=$oldMode; [Console]::OutputEncoding=$oldEncoding
    # Keep fixtures in the ignored workspace for diagnosis.
}
