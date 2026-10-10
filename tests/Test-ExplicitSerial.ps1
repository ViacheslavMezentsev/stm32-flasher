$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $repo 'bin/flash.cmd') -Raw -Encoding UTF8
$start = $source.IndexOf('$StLinkSerialCfgPath =')
$end = $source.IndexOf('$LogStd =', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Selection block not found' }
# Extract the actual selection block, excluding the enclosing preflight brace.
$selection = $source.Substring($start, $end - $start)
$selection = $selection.Substring(0, $selection.LastIndexOf('}'))
$block = [scriptblock]::Create($selection)
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function T($key) { "$key {0}" }
function Write-Info { }
function Write-Warn { }
function Read-Host { throw 'UNEXPECTED MENU' }
function Save-LaunchSetting { }
function Test-IsJLinkEngine($engine) { $engine -eq 'JLINK' }
function Find-JLinkExe { throw 'UNEXPECTED JLINK FALLBACK' }
function Find-CubeProgrammerCli { return 'mock-cube' }
function Get-InfoStLinkInventory {
    $script:inventoryCalls++
    if ($DryRun) { throw 'UNEXPECTED DRYRUN INVENTORY' }
    if ($case -eq 'unavailable') { return $null }
    return Get-StInfoProbeInfo -InventoryOnly
}
function Find-StInfoExe {
    $script:discoveryCalls++
    if ($DryRun) { throw 'UNEXPECTED DRYRUN DISCOVERY' }
    if ($case -eq 'unavailable') { return $null }
    return 'mock-st-info'
}
function Get-StInfoProbeInfo([switch]$InventoryOnly) {
    if (-not $InventoryOnly -and $case -in @('none', 'one', 'many')) { throw 'UNEXPECTED MCU DISCOVERY' }
    if ($DryRun) { throw 'UNEXPECTED DRYRUN DISCOVERY' }
    $entries = @()
    if ($case -in @('one', 'many', 'found')) { $entries += [pscustomobject]@{ Serial = 'OTHER'; Family = 'Fixture' } }
    if ($case -eq 'many') { $entries += [pscustomobject]@{ Serial = 'ANOTHER'; Family = 'Fixture' } }
    if ($case -eq 'found') { $entries += [pscustomobject]@{ Serial = $Serial; Family = 'Fixture' } }
    return [pscustomobject]@{ Count = $entries.Count; Entries = $entries; Warning = $false }
}
$fixture = Join-Path $PSScriptRoot ('.tmp-serial-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    Set-Content (Join-Path $fixture '.stlink_serial') 'OTHER'
    Set-Content (Join-Path $fixture '.jlink_serial') 'OTHER'
    foreach ($SelectedEngine in @('OPENOCD', 'CUBEPROGRAMMER', 'JLINK')) {
        foreach ($type in @('STLINK', 'JLINK')) {
            if (($SelectedEngine -eq 'OPENOCD' -and $type -eq 'JLINK') -or
                ($SelectedEngine -eq 'JLINK' -and $type -eq 'STLINK')) { continue }
            foreach ($case in @('none', 'one', 'many', 'found', 'unavailable')) {
                foreach ($DryRun in @($false, $true)) {
                    $CurrentDir = $fixture
                    $Serial = 'REQUESTED'
                    $SelectedProbeType = $type
                    $ProbeSpecified = $false
                    $FreshProbeSelection = $false
                    $SelectedProbeSerial = ''
                    $SelectedProbeInfo = $null
                    $caught = ''
                    $script:inventoryCalls = 0
                    $script:discoveryCalls = 0
                    try { . $block } catch { $caught = $_.Exception.Message }
                    if ($DryRun) { Assert (($script:inventoryCalls + $script:discoveryCalls) -eq 0) 'DryRun attempted discovery' }
                    $reject = -not $DryRun -and $type -eq 'STLINK' -and $case -in @('none', 'one', 'many')
                    if ($reject) {
                        Assert ($script:discoveryCalls -eq 0) 'Missing serial caused MCU discovery'
                        Assert ($caught -match 'InvalidSerial.*REQUESTED') "Wrong failure: $SelectedEngine/$case : $caught"
                    } else {
                        Assert (-not $caught) "Unexpected failure: $SelectedEngine/$type/$case/$DryRun : $caught"
                        Assert ($SelectedProbeSerial -eq $Serial) "Explicit serial lost: $SelectedEngine/$type/$case/$DryRun"
                        Assert ($SelectedProbeType -eq $type) 'Probe type switched'
                    }
                }
            }
        }
    }
    # Exercise the real command-building statements and retry guard, without
    # starting any engine. TC-33: explicit serial must survive to its arguments.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    Assert (-not $errors.Count) 'PowerShell syntax errors'
    foreach ($name in @('Get-OpenOcdSerialCommand', 'Convert-ToHlaSerial')) {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $Serial = '0123456789ABCDEF01234567'
    $SelectedProbeSerial = $Serial
    $SelectedJLinkSerial = $Serial
    $TargetHex = 'fixture.hex'
    foreach ($SelectedProbeType in @('STLINK', 'JLINK')) {
        $ConnectionPort = if ($SelectedProbeType -eq 'JLINK') { 'JLINK' } else { 'SWD' }
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$ConnectionArgs' }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
        Assert ($ConnectionArgs -eq "port=$ConnectionPort sn=$Serial") 'Cube serial binding lost'
    }
    foreach ($needle in @('$ExeArgs += @("-usb", $SelectedJLinkSerial)', '$ExeArgs += @("-c", "`"$(Get-OpenOcdSerialCommand $SelectedProbeSerial plain)`"")')) {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Extent.Text -eq $needle }, $true)
        Assert ($null -ne $node) 'Serial argument statement not found'
        $ExeArgs = @()
        . ([scriptblock]::Create($node.Extent.Text))
        Assert (($ExeArgs -join ' ') -match $Serial) 'Engine serial binding lost'
    }
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$savedJLinkSerialWasUsed' }, $true)
    $Erase = $false
    $RetryArgsWithoutSerial = @('unsafe-default')
    foreach ($SelectedEngine in @('JLINK', 'CUBEPROGRAMMER')) {
        $SelectedProbeType = 'JLINK'
        . ([scriptblock]::Create($node.Extent.Text))
        Assert (-not $savedJLinkSerialWasUsed) 'Explicit serial allows retry without serial'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Explicit serial selection tests passed.'
