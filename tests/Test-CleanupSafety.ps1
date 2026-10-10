param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
# TC-17: real CMD wrappers and junctions; all targets stay inside this fixture.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-cleanup-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $root 'work'
$outside = Join-Path $root 'outside'
$links = New-Object 'System.Collections.Generic.List[string]'
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Assert-InFixture($path) {
    $full = [IO.Path]::GetFullPath($path)
    Assert ($full.StartsWith(([IO.Path]::GetFullPath($root).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) "Outside fixture: $path"
}
function Write-Fixture($relative) {
    $path = Join-Path $work $relative
    Assert-InFixture $path
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value "fixture:$relative" -Encoding ASCII
}
function Snapshot($directory) {
    # Do not recurse into reparse points, including when testing PS5.1.
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($directory)
    $entries = while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { "LINK $($item.FullName) $($item.Target)" }
            elseif ($item.PSIsContainer) { "DIR $($item.FullName)"; $pending.Push($item.FullName) }
            else { "$($item.FullName) $((Get-FileHash -LiteralPath $item.FullName).Hash)" }
        }
    }
    return (($entries | Sort-Object) -join "`n")
}
function Add-Junction($relative) {
    $path = Join-Path $work $relative
    Assert-InFixture $path
    Assert-InFixture $outside
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    New-Item -ItemType Junction -Path $path -Target $outside | Out-Null
    $links.Add($path)
}
function Remove-Junctions {
    foreach ($path in $links) {
        Assert-InFixture $path
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item) {
            Assert ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) "Not a junction: $path"
            # Delete the junction itself, never its target or contents.
            [IO.Directory]::Delete($path, $false)
        }
    }
    $links.Clear()
}
$settings = @('.flash.json','.flash_engine','.probe_type','.stlink_serial','.jlink_serial','.jlink_device','.openocd_target')
$artifacts = @('flash_log.txt','flash_log.txt.stdout','flash_log.txt.stderr','report.html','.jlink_flash.jlink',
    '.history/session/report.html','.tools/stlink/bin/st-info.exe','.tools/stlink.zip','.tools/openocd.zip',
    '.tools/xpack-openocd-0.12.0-3/bin/openocd.exe','.flash_read_11111111111111111111111111111111.bin',
    '.flash_backup_22222222222222222222222222222222.hex','.flash_config_33333333333333333333333333333333.tmp')
$preserved = @('firmware.hex','firmware.hex.sha256','image.bin','notes.md','backups/before.hex',
    'backups/before.hex.sha256','.tools/user-tool/keep.txt','.flash_read_invalid.bin',
    '.flash_read_11111111111111111111111111111111.txt','.flash_config_notes.tmp','flash.cmd','forget.cmd')
function Seed {
    foreach ($name in ($settings + $artifacts + ($preserved | Where-Object { $_ -notin @('flash.cmd','forget.cmd') }))) { Write-Fixture $name }
}
function Check-Preserved($hashes) {
    foreach ($name in $preserved) {
        $path = Join-Path $work $name
        Assert (Test-Path -LiteralPath $path -PathType Leaf) "Removed user file: $name"
        Assert ((Get-FileHash -LiteralPath $path).Hash -eq $hashes[$name]) "Changed user file: $name"
    }
}
function Run-Cleanup($arguments, $expected, $wrapper = 'forget') {
    $before = Snapshot $work
    $outsideBefore = Snapshot $outside
    Push-Location $work
    try {
        # PS5.1 wraps expected native stderr in ErrorRecord objects.
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $env:ComSpec /d /c "`"$work\$wrapper.cmd`" $arguments" 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $savedPreference }
    } finally { Pop-Location }
    Assert ($code -eq $expected) "Exit $code expected $expected : $arguments`n$output"
    Assert ($output -notmatch 'FORBIDDEN CLEANUP SIDE EFFECT') 'Cleanup reached hardware/execution'
    Assert ((Snapshot $outside) -ceq $outsideBefore) 'Files outside working directory changed'
    if ($arguments -match '-DryRun') { Assert ((Snapshot $work) -ceq $before) 'DryRun changed files' }
    if ($expected -ne 0) { Assert ($output -match 'Linked cleanup') "Missing link diagnostic: $output" }
}
try {
    New-Item -ItemType Directory -Path $work, $outside | Out-Null
    foreach ($name in @('sentinel.hex','sentinel.hex.sha256','report.html')) { Set-Content (Join-Path $outside $name) "outside:$name" -Encoding ASCII }
    New-Item -ItemType Directory -Path (Join-Path $outside 'stlink') | Out-Null
    Set-Content (Join-Path $outside 'stlink/keep.txt') 'outside-tool'
    $source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
    $guards = @'
function Stop-Forbidden { [Console]::Error.WriteLine('FORBIDDEN CLEANUP SIDE EFFECT'); exit 97 }
foreach ($name in @('Get-CimInstance','Get-WmiObject','Get-JLinkProbes','Get-StInfoProbeInfo',
    'Invoke-ProbeInventory','Start-Process','Invoke-WebRequest','Invoke-RestMethod','Invoke-Item','Read-Host')) {
    Set-Item -Path "function:$name" -Value { Stop-Forbidden }
}
'@
    $position = $source.IndexOf('$CurrentDir     =')
    Assert ($position -gt 0 -and $source.Contains('$OpenOcdUrl     =')) 'Guard insertion points missing'
    $source = $source.Insert($position, $guards + "`n").Replace('$OpenOcdUrl     =', 'Stop-Forbidden; $OpenOcdUrl     =')
    $source = $source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $work 'flash.cmd'), $source, (New-Object Text.UTF8Encoding($false)))
    Copy-Item (Join-Path $repo 'bin/forget.cmd') $work
    Seed
    $hashes = @{}
    foreach ($name in $preserved) { $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $work $name)).Hash }
    Run-Cleanup '-DryRun' 0
    Run-Cleanup '-ResetConfig -DryRun' 0 'flash'
    Run-Cleanup '-ResetConfig' 0 'flash'
    foreach ($name in $settings) { Assert (-not (Test-Path -LiteralPath (Join-Path $work $name))) "Setting left: $name" }
    foreach ($name in $artifacts) { Assert (Test-Path -LiteralPath (Join-Path $work $name)) "Reset removed artifact: $name" }
    Check-Preserved $hashes
    Seed
    Run-Cleanup '' 0
    foreach ($name in ($settings + $artifacts)) { Assert (-not (Test-Path -LiteralPath (Join-Path $work $name))) "Artifact left: $name" }
    Check-Preserved $hashes
    foreach ($relative in @('.history','.tools/stlink','.history/nested')) {
        Add-Junction $relative
        try {
            Run-Cleanup '-DryRun' 1
            Run-Cleanup '' 1
            Check-Preserved $hashes
        } finally { Remove-Junctions }
    }
    # A separate workspace tests a linked parent without replacing user tools.
    $originalWork = $work
    $work = Join-Path $root 'linked-parent'
    New-Item -ItemType Directory -Path $work | Out-Null
    Copy-Item (Join-Path $originalWork 'flash.cmd'), (Join-Path $originalWork 'forget.cmd') $work
    Add-Junction '.tools'
    try { Run-Cleanup '-DryRun' 1; Run-Cleanup '' 1 } finally { Remove-Junctions }
    Add-Junction '.flash_engine'
    try {
        Run-Cleanup '-ResetConfig -DryRun' 1 'flash'
        Run-Cleanup '-ResetConfig' 1 'flash'
    } finally { Remove-Junctions }
} finally {
    Remove-Junctions
    $resolved = [IO.Path]::GetFullPath($root)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture root'
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host 'Cleanup safety tests passed; user files and junction targets preserved.'
