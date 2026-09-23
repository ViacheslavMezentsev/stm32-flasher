param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $repo 'flash.cmd') -Raw -Encoding UTF8
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
function Assert($condition, $message) { if (-not $condition) { throw $message } }
foreach ($name in @('ConvertTo-MemoryNumber', 'New-IntelHexRecord', 'Write-IntelHex', 'Get-ReadSizeFromLog', 'Test-BackupReadLog', 'Get-BackupFileName')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function T($key) { $key }
function Write-Warn($message) { Write-Host $message }
Assert ((ConvertTo-MemoryNumber '0x10000') -eq 65536) 'Hex size parsing'
Assert ((Get-ReadSizeFromLog JLINK '1FFFF7E0 = 0040' STM32F103C8) -eq 65536) 'F1 Flash size register'
Assert ((Get-ReadSizeFromLog JLINK '1FFFF7E0 = 0080' STM32F103C8) -eq 0) 'Conflicting Flash size must not be assumed'
Assert ((Get-ReadSizeFromLog CUBEPROGRAMMER 'Flash size : 128 KBytes' '') -eq 131072) 'Cube Flash size'
Assert ((Get-ReadSizeFromLog OPENOCD "FLASH_BACKUP_BANK 134217728 65536`n" '') -eq 65536) 'OpenOCD bank size'
Assert ((Get-ReadSizeFromLog OPENOCD "FLASH_BACKUP_BANK 134217728 65536`nFLASH_BACKUP_BANK 134348800 65536`n" '') -eq 0) 'Disjoint banks cannot be inferred as a contiguous range'
Assert (-not (Test-BackupReadLog JLINK 'Cannot read memory')) 'Read error accepted'
Assert (Test-BackupReadLog JLINK 'Reading 65536 bytes from addr 0x08000000 into file...O.K.') 'J-Link read success'
$stamp = [DateTime]::new(2026, 9, 24, 0, 53, 18)
Assert ((Get-BackupFileName STM32 'Device ID : 0x415' '' 65536 $stamp) -ceq 'STM32_20260924_005318_ID0x415_64K.hex') 'Cube backup filename'
Assert ((Get-BackupFileName STM32 'device idcode = 0x20036409' '' 131072 $stamp) -ceq 'STM32_20260924_005318_ID0x409_128K.hex') 'Revision bits leaked into filename'
Assert ((Get-BackupFileName STM32F103C8 'E0042000 = 20036410' '' 65536 $stamp) -ceq 'STM32F103C8_20260924_005318_ID0x410_64K.hex') 'J-Link DBGMCU ID'
Assert ((Get-BackupFileName STM32 'DPIDR: 0x2BA01477' '' 1025 $stamp) -ceq 'STM32_20260924_005318_IDunknown_2K.hex') 'Unknown MCU ID / rounding'
Assert ((Get-BackupFileName STM32 '' '0x409' 1024 $stamp) -match '_ID0x409_1K.hex$') 'ST-Link ID fallback'

$fixture = Join-Path $repo ('.backup-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
Push-Location $fixture
try {
    $data = New-Object byte[] 65553
    for ($i = 0; $i -lt $data.Length; $i++) { $data[$i] = ($i * 37) % 256 }
    [IO.File]::WriteAllBytes((Join-Path $fixture 'input.bin'), $data)
    Write-IntelHex (Join-Path $fixture 'input.bin') (Join-Path $fixture 'boundary.hex') 0x0800FFF7
    $decoded = New-Object 'System.Collections.Generic.List[byte]'
    $upper = 0L; $expectedAddress = 0x0800FFF7L; $eof = $false
    foreach ($line in Get-Content boundary.hex) {
        Assert ($line.StartsWith(':')) 'Missing HEX colon'
        $record = @()
        for ($i = 1; $i -lt $line.Length; $i += 2) { $record += [Convert]::ToInt32($line.Substring($i, 2), 16) }
        Assert ((($record | Measure-Object -Sum).Sum % 256) -eq 0) 'HEX checksum mismatch'
        Assert ($record.Count -eq $record[0] + 5) 'HEX record length mismatch'
        switch ($record[3]) {
            4 { $upper = ($record[4] * 256L + $record[5]) * 65536L }
            0 {
                Assert (($upper + $record[1] * 256 + $record[2]) -eq $expectedAddress) 'HEX address gap'
                for ($i = 0; $i -lt $record[0]; $i++) { $decoded.Add([byte]$record[4 + $i]); $expectedAddress++ }
            }
            1 { Assert ($line -eq ':00000001FF') 'Invalid EOF'; $eof = $true }
            default { throw 'Unexpected HEX record' }
        }
    }
    Assert $eof 'Missing HEX EOF'
    Assert ([Convert]::ToBase64String($data) -ceq [Convert]::ToBase64String($decoded.ToArray())) 'HEX roundtrip changed data'

    # Replace tool discovery/execution only; exercise the real backup and report flow in a child process.
    $mocks = @'
function Find-CubeProgrammerCli { (Get-Process -Id $PID).Path }
function Find-JLinkExe { (Get-Process -Id $PID).Path }
function Find-StInfoExe { return $null }
function Get-CimInstance { return $null }
function Get-JLinkProbes { [PSCustomObject]@{ Serial = '123'; Type = 'JLINK'; Family = 'Fixture' } }
function Get-UsbStLinkProbes { [PSCustomObject]@{ Serial = '456'; Type = 'STLINK'; Family = 'Fixture' } }
function Invoke-Item { }
function Invoke-ReadTool($exe, $arguments) {
    $script:ReadCalls++
    if ($arguments -contains '-u') {
        $length = if ($env:FLASH_TEST_CASE -eq 'short') { 15 } else { 16 }
        $bytes = New-Object byte[] $length
        for ($i = 0; $i -lt $length; $i++) { $bytes[$i] = $i }
        [IO.File]::WriteAllBytes($arguments[-1].Trim('"'), $bytes)
        $message = if ($env:FLASH_TEST_CASE -eq 'protected') { 'Error: Read protection' } else { "Device ID : 0x410`nData read successfully" }
        return [PSCustomObject]@{ ExitCode = 0; Log = $message }
    }
    return [PSCustomObject]@{ ExitCode = 0; Log = 'Flash size : 64 KBytes' }
}
'@
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Cannot inject tool mocks'
    $mockScript = $source.Insert($position, $mocks + "`n")
    $mockPath = Join-Path $fixture 'mock-flash.ps1'
    Set-Content -LiteralPath $mockPath -Value $mockScript -Encoding UTF8
    foreach ($case in @('good', 'short', 'protected')) {
        $env:FLASH_TEST_CASE = $case
        $result = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Backup -Engine CUBE -Probe JLINK -Serial 123 -Size 16 -Output "backups/$case.hex" 2>&1
        $code = $LASTEXITCODE
        if ($case -eq 'good') {
            Assert ($code -eq 0) ($result | Out-String)
            Assert (Test-Path backups/good.hex.sha256) 'Missing backup checksum'
            $expected = (Get-FileHash backups/good.hex -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert ((Get-Content backups/good.hex.sha256) -eq "$expected *good.hex") 'Wrong backup checksum'
        } else {
            Assert ($code -ne 0) "Failed read reported as success: $case"
            Assert (-not (Test-Path "backups/$case.hex")) 'Failed read published a HEX file'
        }
        Assert (@(Get-ChildItem -Force -Filter '.flash_backup_*').Count -eq 0) 'Temporary backup files left behind'
    }
    $originalHash = (Get-FileHash backups/good.hex).Hash
    $null = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Backup -Engine CUBE -Probe JLINK -Serial 123 -Size 16 -Output backups/good.hex
    Assert ($LASTEXITCODE -ne 0) 'Existing backup was accepted for overwrite'
    Assert ((Get-FileHash backups/good.hex).Hash -eq $originalHash) 'Existing backup changed'
    $env:FLASH_TEST_CASE = 'good'
    $null = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Backup -Engine CUBE -Probe JLINK -Serial 123 -Size 16
    Assert ($LASTEXITCODE -eq 0) 'Automatic backup name failed'
    $automatic = @(Get-ChildItem backups -Filter 'STM32_*_ID0x410_1K.hex')
    Assert ($automatic.Count -eq 1) 'Automatic filename missing MCU ID or image size'
    Assert ($automatic[0].Name -match '^STM32_\d{8}_\d{6}_ID0x410_1K\.hex$') 'Unexpected timestamp or random suffix'
    Assert ((Get-Content ($automatic[0].FullName + '.sha256')) -match ([regex]::Escape('*' + $automatic[0].Name) + '$')) 'Checksum references wrong automatic filename'
    $beforeInfo = Get-ChildItem -Recurse -Force -File | Get-FileHash | Select-Object Path, Hash | ConvertTo-Json
    $null = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Info
    Assert ($LASTEXITCODE -eq 0) 'Environment info failed'
    $null = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Info -ProbeTarget -Engine CUBE -Probe JLINK -Serial 123
    Assert ($LASTEXITCODE -eq 0) 'Target info failed'
    $afterInfo = Get-ChildItem -Recurse -Force -File | Get-FileHash | Select-Object Path, Hash | ConvertTo-Json
    Assert ($beforeInfo -ceq $afterInfo) 'Info modified settings, report or history'
    $null = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -Command ". ([scriptblock]::Create((Get-Content -LiteralPath '$mockPath' -Raw -Encoding UTF8)))" -Clean
    Assert ($LASTEXITCODE -eq 0) 'Cleanup failed'
    Assert ((Get-FileHash backups/good.hex).Hash -eq $originalHash) 'Cleanup removed backup'
} finally {
    Remove-Item Env:FLASH_TEST_CASE -ErrorAction SilentlyContinue
    Pop-Location
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Backup tests passed.'
