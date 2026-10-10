param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-directory-lock-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $root 'work space'
$other = Join-Path $root 'other'
$holder = $null
$observer = $null
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Start-TestProcess($exe, $arguments, $directory, $environment = @{}) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = $arguments
    $start.WorkingDirectory = $directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($key in $environment.Keys) { $start.EnvironmentVariables[$key] = $environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    return @{ Process=$process; Out=$process.StandardOutput.ReadToEndAsync(); Err=$process.StandardError.ReadToEndAsync() }
}
function Finish-TestProcess($item) {
    try {
        if (-not $item.Process.WaitForExit(30000)) { $item.Process.Kill(); throw 'Process timeout' }
        Assert ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($item.Out,$item.Err),5000)) 'Output timeout'
        return @{ Code=$item.Process.ExitCode; Text=($item.Out.Result + $item.Err.Result) }
    } finally { $item.Process.Dispose() }
}
function Run-Cmd($command, $directory = $work) {
    Finish-TestProcess (Start-TestProcess $env:ComSpec ("/d /c $command") $directory)
}
function Start-Holder($mode = 'cancel') {
    $ready = Join-Path $root ([guid]::NewGuid().ToString('N') + '.ready')
    $gate = "$ready.gate"
    $script = Join-Path $work 'flash.cmd'
    $code = ". ([scriptblock]::Create((Get-Content -LiteralPath '$($script.Replace("'","''"))' -Raw -Encoding UTF8))) -Setup -Lang en"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $item = Start-TestProcess $PowerShellExe "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" $work @{
        LOCKTEST_READY=$ready; LOCKTEST_GATE=$gate; LOCKTEST_MODE=$mode
    }
    $item.Gate = $gate
    $limit = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $ready) -and -not $item.Process.HasExited -and [DateTime]::UtcNow -lt $limit) { Start-Sleep -Milliseconds 50 }
    if (-not (Test-Path -LiteralPath $ready)) {
        if (-not $item.Process.HasExited) { $item.Process.Kill() }
        $result = Finish-TestProcess $item
        throw "Holder not ready: $($result.Text)"
    }
    return $item
}
function Snapshot {
    @(Get-ChildItem -LiteralPath $work -Force -File | Sort-Object Name | Get-FileHash | Select-Object Path,Hash) | ConvertTo-Json -Compress
}
$mocks = @'
function Find-CubeProgrammerCli { @() }
function Find-JLinkExe { $null }
function Find-OpenOcdInstallation { $null }
function Show-EnvironmentInfo { Write-Output 'INFO_WITHOUT_MCU' }
function Invoke-Download { throw 'UNEXPECTED_NETWORK' }
function Get-StInfoProbeInfo { throw 'UNEXPECTED_MCU' }
function Invoke-ReadTool { throw 'UNEXPECTED_MCU' }
function Read-Host {
    if (-not $env:LOCKTEST_READY) { throw 'UNEXPECTED_INPUT' }
    [IO.File]::WriteAllText($env:LOCKTEST_READY, 'ready')
    $limit = [DateTime]::UtcNow.AddSeconds(180)
    while (-not (Test-Path -LiteralPath $env:LOCKTEST_GATE)) {
        if ([DateTime]::UtcNow -gt $limit) { throw 'HOLDER_TIMEOUT' }
        Start-Sleep -Milliseconds 50
    }
    if ($env:LOCKTEST_MODE -eq 'error') { throw 'EXPECTED_SETUP_ERROR' }
    return 'q'
}
'@
try {
    New-Item -ItemType Directory -Path $work,$other | Out-Null
    $source = Get-Content -LiteralPath (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert (-not $errors.Count) 'Script parse error'
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DirectoryMutexName' },$true)
    . ([scriptblock]::Create($node.Extent.Text))
    Assert ((Get-DirectoryMutexName $work) -eq (Get-DirectoryMutexName ($work.ToUpperInvariant() + '\.\'))) 'Case/trailing separator normalization'
    Assert ((Get-DirectoryMutexName $work) -ne (Get-DirectoryMutexName $other)) 'Different directory identity'
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0) 'Missing mock injection point'
    $modified = $source.Insert($position, $mocks + "`r`n")
    $modified = $modified -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    foreach ($dir in @($work,$other)) {
        [IO.File]::WriteAllText((Join-Path $dir 'flash.cmd'), $modified, (New-Object Text.UTF8Encoding($false)))
        foreach ($name in @('erase','backup','info','forget','setup')) { Copy-Item -LiteralPath (Join-Path $repo "bin/$name.cmd") -Destination $dir }
        Set-Content -LiteralPath (Join-Path $dir '.flash_engine') -Value 'OPENOCD'
    }
    Set-Content -LiteralPath (Join-Path $work 'firmware.hex') -Value ":0400000001020304F2`r`n:00000001FF" -Encoding ASCII
    foreach ($file in @('report.html','flash_log.txt')) { Set-Content -LiteralPath (Join-Path $work $file) -Value 'sentinel' }
    $holder = Start-Holder
    $before = Snapshot
    $otherHostName = if ($PSVersionTable.PSVersion.Major -ge 7) { 'powershell.exe' } else { 'pwsh.exe' }
    $otherHost = Get-Command $otherHostName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($otherHost) {
        $script = Join-Path $work 'flash.cmd'
        $code = ". ([scriptblock]::Create((Get-Content -LiteralPath '$($script.Replace("'","''"))' -Raw -Encoding UTF8))) -ResetConfig -Lang en"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $result = Finish-TestProcess (Start-TestProcess $otherHost.Source "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" $work)
        Assert ($result.Code -eq 1 -and $result.Text -match 'already running in this directory') 'Cross-PowerShell contender bypassed lock'
    }
    foreach ($lang in @('en','ru')) {
        foreach ($command in @('flash.cmd','erase.cmd','backup.cmd','setup.cmd','forget.cmd','flash.cmd -ResetConfig','info.cmd -ProbeTarget')) {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $result = Run-Cmd "$command -Lang $lang"
            Assert ($result.Code -eq 1 -and $result.Text -match 'stm32-flasher' -and $result.Text -notmatch 'UNEXPECTED_|HOLDER_TIMEOUT') "Contender failed: $command $($result.Text)"
            $expected = if ($lang -eq 'en') { 'already running in this directory' } else { [regex]::Unescape('\u0412 \u044d\u0442\u043e\u0439 \u043f\u0430\u043f\u043a\u0435') }
            Assert ($result.Text -match $expected) "Missing localized busy message: $($result.Text)"
            Assert ($watch.Elapsed.TotalSeconds -lt 15) 'Contender waited for owner'
        }
    }
    foreach ($command in @(
        'setup.cmd --help','erase.cmd --version','info.cmd',
        'setup.cmd -DryRun','forget.cmd -DryRun',
        'flash.cmd -DryRun -HexFile firmware.hex -Engine OPENOCD -Target target/stm32f1x.cfg',
        'erase.cmd -DryRun -Engine OPENOCD -Target target/stm32f1x.cfg',
        'backup.cmd -DryRun -Engine OPENOCD -Target target/stm32f1x.cfg -Size 64',
        'info.cmd -DryRun -ProbeTarget -Engine OPENOCD -Target target/stm32f1x.cfg')) {
        $result = Run-Cmd "$command -Lang en"
        Assert ($result.Code -eq 0 -and $result.Text -notmatch 'UNEXPECTED_') "Read-only command blocked: $command $($result.Text)"
    }
    Assert ((Snapshot) -eq $before) 'Contenders/read-only commands changed protected files'
    $result = Run-Cmd 'flash.cmd -ResetConfig -Lang en' $other
    Assert ($result.Code -eq 0) 'Independent directory blocked'
    Set-Content -LiteralPath $holder.Gate -Value 'continue'
    $result = Finish-TestProcess $holder; $holder = $null
    Assert ($result.Code -eq 0) 'Setup cancellation failed'
    $result = Run-Cmd 'flash.cmd -ResetConfig -Lang en'
    Assert ($result.Code -eq 0) 'Lock retained after normal exit'
    $holder = Start-Holder 'error'
    Set-Content -LiteralPath $holder.Gate -Value 'continue'
    $result = Finish-TestProcess $holder; $holder = $null
    Assert ($result.Code -eq 1) 'Setup error exit lost'
    $result = Run-Cmd 'flash.cmd -ResetConfig -Lang en'
    Assert ($result.Code -eq 0) 'Lock retained after error'
    $holder = Start-Holder
    # Keep the kernel object alive to exercise the abandoned-mutex path.
    $observer = [Threading.Mutex]::OpenExisting((Get-DirectoryMutexName $work))
    $holder.Process.Kill()
    $null = Finish-TestProcess $holder; $holder = $null
    $result = Run-Cmd 'flash.cmd -ResetConfig -Lang en'
    Assert ($result.Code -eq 0 -and $result.Text -match 'previous process ended unexpectedly') "Abandoned lock not recovered: $($result.Text)"
    $observer.Dispose(); $observer = $null
    $broken = $source.Insert($position, "function Enter-DirectoryLock { throw 'EXPECTED_LOCK_ERROR' }`r`n")
    $broken = $broken -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $other 'flash.cmd'), $broken, (New-Object Text.UTF8Encoding($false)))
    Set-Content -LiteralPath (Join-Path $other '.flash_engine') -Value 'sentinel'
    $result = Run-Cmd 'flash.cmd -ResetConfig -Lang en' $other
    Assert ($result.Code -eq 1 -and $result.Text -match 'Unable to lock the working directory') 'Lock error not reported'
    Assert ((Get-Content -LiteralPath (Join-Path $other '.flash_engine') -Raw).Trim() -eq 'sentinel') 'Operation ran after lock failure'
    Assert (-not @(Get-ChildItem -LiteralPath $work -Force | Where-Object { $_.Name -match 'lock|mutex' }).Count) 'Persistent lock artifact'
    Write-Output 'Directory lock tests passed without hardware.'
} finally {
    if ($holder) {
        if (-not $holder.Process.HasExited) { $holder.Process.Kill(); [void]$holder.Process.WaitForExit(5000) }
        $holder.Process.Dispose()
    }
    if ($observer) { $observer.Dispose() }
    $resolved = [IO.Path]::GetFullPath($root)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
