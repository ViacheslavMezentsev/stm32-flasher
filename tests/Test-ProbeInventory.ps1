$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput((Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-LaunchSettingMap', 'Invoke-ProbeInventory', 'ConvertFrom-CubeProbeList', 'Get-InfoStLinkInventory', 'Get-UsbStLinkProbes', 'Get-RunningScriptHash')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Assert($value, $message) { if (-not $value) { throw $message } }
$identityRoot=Join-Path $PSScriptRoot ('.tmp-identity-' + [guid]::NewGuid().ToString('N'))
$oldScriptPath=$env:SCRIPT_PATH
try {
    New-Item -ItemType Directory (Join-Path $identityRoot 'other') -Force | Out-Null
    $first=Join-Path $identityRoot 'flash.cmd'
    $second=Join-Path $identityRoot 'other/flash.cmd'
    Copy-Item (Join-Path $repo 'bin/flash.cmd') $first
    Copy-Item $first $second
    $expected=(Get-FileHash $first -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ((Get-RunningScriptHash $first) -ceq $expected) 'Hash must cover exact file bytes'
    Assert ((Get-RunningScriptHash $second) -ceq $expected) 'Identical copies must have equal hashes'
    Add-Content $second "`n# identity fixture" -Encoding UTF8
    $env:SCRIPT_PATH=$second
    Push-Location $identityRoot
    try {
        $changed=Get-RunningScriptHash
        Assert ($changed -cne $expected -and $changed -ceq (Get-FileHash $second).Hash.ToLowerInvariant()) 'Hash must use launched path, not cwd copy or version'
    } finally { Pop-Location }
    Assert (-not (Get-RunningScriptHash (Join-Path $identityRoot 'missing.cmd'))) 'Missing file must not abort info'
    Assert (-not (Get-RunningScriptHash '')) 'Unknown source must not fall back to cwd'
} finally {
    $env:SCRIPT_PATH=$oldScriptPath
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($identityRoot))) -ne $PSScriptRoot) { throw 'Invalid identity fixture path' }
    Remove-Item -LiteralPath $identityRoot -Recurse -Force
}
$hostExe = (Get-Process -Id $PID).Path
$capture = Invoke-ProbeInventory $hostExe '-NoProfile -Command "[Console]::WriteLine(''out''); [Console]::Error.WriteLine(''err'')"'
Assert ($capture -match 'out' -and $capture -match 'err') 'Capture stdout and stderr without files'
Assert (-not (Invoke-ProbeInventory $hostExe '-NoProfile -Command "exit 1"')) 'Reject failed process'
Assert (-not (Invoke-ProbeInventory (Join-Path $repo 'missing-probe-tool.exe') '--help')) 'Handle missing executable'
$sample = @'
===== J-Link Interface =====
J-Link Probe 0 :
    J-Link SN : 12345678
-------- Connected ST-LINK Probes List --------
ST-Link Probe 0 :
   ST-LINK SN : 111111111111111111111111
   Board Name :
ST-Link Probe 1 :
   ST-LINK SN : 222222222222222222222222
   Board Name :
ST-Link Probe 2 :
   ST-LINK SN : 333333333333333333333333
   Board Name : NUCLEO-F030R8
ST-Link Probe 3 :
   ST-LINK SN : 444444444444444444444444
   Board Name :
-----------------------------------------------
===== UART Interface =====
ST-LINK SN : 111111111111111111111111
'@
foreach ($text in @($sample, $sample.Replace("`n", "`r`n"))) {
    $parsed = ConvertFrom-CubeProbeList $text
    Assert ($parsed.Entries.Count -eq 4) 'Must exclude J-Link and UART duplicates'
    Assert ($parsed.Entries[3].Serial -eq '444444444444444444444444') 'Fourth serial'
    Assert ($parsed.Entries[2].Family -eq 'NUCLEO-F030R8') 'Board name'
    Assert ($parsed.Entries[0].Family -eq 'ST-Link') 'Blank board name'
}
$bad = "ST-LINK error (DEV_CONNECT_ERR)`n" + $sample.Replace('444444444444444444444444', '7&00000000&0&2')
$parsed = ConvertFrom-CubeProbeList $bad
Assert ($parsed.Warning -and -not $parsed.Entries[3].Serial) 'Never expose Windows ID as serial'
Assert ($parsed.Entries[3].InstanceId -eq '7&00000000&0&2') 'Keep diagnostic ID'
Assert (-not (ConvertFrom-CubeProbeList 'unexpected output')) 'Reject unsupported format'
function Get-CimInstance {
    @(
        [PSCustomObject]@{ PNPDeviceID = 'USB\VID_0483&PID_3748\7&00000000&0&2'; Name = 'STM32 STLink' },
        [PSCustomObject]@{ PNPDeviceID = 'USB\VID_0483&PID_3752\111111111111111111111111'; Name = 'ST-Link' }
    )
}
$usb = @(Get-UsbStLinkProbes)
Assert ($usb.Count -eq 2 -and -not $usb[0].Serial -and $usb[1].Serial) 'Windows fallback serial validation'
function Invoke-ProbeInventory($exe, $arguments) {
    $script:calls += "$exe $arguments"
    if ($exe -eq 'unsupported') { return 'old help' }
    if ($exe -eq 'failed') { return $null }
    if ($arguments -eq '--help') { return '<stlink-only>' }
    Assert ($arguments -eq '-l stlink-only') 'Unsafe inventory arguments'
    return $sample
}
$calls = @()
$result = Get-InfoStLinkInventory @('unsupported', 'failed', 'supported')
Assert ($result.Source -eq 'supported' -and $result.Entries.Count -eq 4) 'Try next installation'
Assert ($calls -notcontains 'unsupported -l stlink-only') 'Never invoke unknown list option'
$result = Get-InfoStLinkInventory @('unsupported', 'failed')
Assert ($result.Source -eq 'Windows USB' -and $result.Entries.Count -eq 2) 'Fallback on unsupported or failed invocation'
$result = Get-InfoStLinkInventory @()
Assert ($result.Source -eq 'Windows USB') 'Fallback without CubeProgrammer'
# Exercise the real presentation function with no native tools or filesystem changes.
& {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-WindowsJLinkPresent'},$true)
    . ([scriptblock]::Create($node.Extent.Text))
    function Invoke-DoctorQuery($exe,$arguments) {
        Assert ($arguments -match '-NoProfile -NonInteractive -EncodedCommand ') 'Unbounded or interactive OS query'
        $code=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($arguments -split ' ')[-1]))
        Assert ($code.Contains("`$ProgressPreference='SilentlyContinue'") -and $code.Contains('Get-PnpDevice -PresentOnly -ErrorAction Stop')) 'OS query must exclude stale devices and progress output'
        return $script:osQuery
    }
    foreach ($state in @('Known','Unknown','Timeout','Error')) {
        $script:osQuery=@{State=$state;Text='JLINK_USB_PRESENT'}
        Assert ((Test-WindowsJLinkPresent) -eq ($state -eq 'Known')) 'Failed OS query must not claim presence'
    }
    foreach ($text in @('','garbled')) {
        $script:osQuery=@{State='Known';Text=$text}
        Assert (-not (Test-WindowsJLinkPresent)) 'Missing marker must not claim presence'
    }
}
& {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-EnvironmentInfo' }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
    foreach ($dict in @('$LangRu', '$LangEn')) {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $dict }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    function T($key) { $language[$key] }
    function Write-Step($number, $label) { Write-Output "SECTION:$number" }
    function Write-Info($text) { Write-Output $text }
    function Write-Warn($text) { Write-Output "WARNING:$text" }
    function Find-CubeProgrammerCli { }
    function Find-JLinkExe { }
    function Find-StInfoExe { }
    function Get-InfoEnginePath { }
    function Read-LaunchConfiguration { @{ Values=@{}; Source='none' } }
    function Get-Command { }
    function Test-Path { $false }
    function Get-ChildItem { }
    function Get-InfoStLinkInventory {
        [PSCustomObject]@{ Source = 'fixture'; Warning = $false; Entries = @([PSCustomObject]@{ Type = 'STLINK'; Serial = '444444444444444444444444'; Family = 'ST-Link' }) }
    }
    function Get-JLinkProbes {
        if ($case -in @('windows-only','windows-absent')) { return }
        if ($case -eq 'timeout') { throw [TimeoutException]::new((T 'JLinkTimeout')) }
        if ($case -eq 'error') { throw 'J-Link test error' }
        [PSCustomObject]@{ Type = 'JLINK'; Serial = '12345678'; Family = 'J-Link CE' }
    }
    $CurrentDir = $repo
    function Test-WindowsJLinkPresent { $case -eq 'windows-only' }
    function Get-RunningScriptHash { if ($case -eq 'error') { return $null }; return ('a' * 64) }
    foreach ($language in @($LangRu, $LangEn)) {
        foreach ($case in @('timeout', 'error', 'success', 'windows-only', 'windows-absent')) {
            $output = @(Show-EnvironmentInfo) -join "`n"
            $expectedIdentity=if ($case -eq 'error') { $language.InfoHashUnavailable } else { 'a' * 64 }
            Assert ($output.Contains("flash.cmd SHA-256: $expectedIdentity")) 'Missing script identity or localized fallback'
            Assert ($output.Contains('444444444444444444444444')) 'ST-Link lost on J-Link failure'
            Assert ($output.Contains('SECTION:5')) 'Inventory stopped after J-Link failure'
            Assert ($output.Contains($language.JLinkWindowsOnly) -eq ($case -eq 'windows-only')) 'Incorrect OS presence warning'
            if ($case -in @('timeout','error','windows-only')) {
                Assert ($output.IndexOf('WARNING:') -gt $output.IndexOf('SECTION:4')) 'Warning appeared before USB section'
                Assert ($output.IndexOf('WARNING:') -lt $output.IndexOf('SECTION:5')) 'Warning appeared after USB section'
            }
            if ($case -eq 'timeout') {
                Assert ($output.Contains($language.JLinkTimeout) -and $output.Contains($language.InfoJLinkRetry)) 'Missing localized timeout guidance'
                Assert (-not $output.Contains($language.NoDebugger)) 'Misleading generic probe warning'
            } else {
                Assert (-not $output.Contains($language.InfoJLinkRetry)) 'Timeout guidance for another outcome'
            }
            if ($case -eq 'success') { Assert ($output.Contains('12345678') -and -not $output.Contains('WARNING:')) 'Normal J-Link listing changed' }
        }
    }
}
Write-Output 'Probe inventory tests passed.'
