$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/flash.cmd') -Raw -Encoding UTF8
$tokens=$null; $errors=$null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Invalid script syntax' }
foreach ($name in @('Get-DoctorPassport','New-DoctorFinding','Get-DoctorAssessment')) {
    $nodes = @($ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($nodes.Count -ne 1) { throw "Missing function: $name" }
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function New-Facts {
    @{
        Runtime='Supported'; Config='Valid'
        Engine=@{ State='Available'; Name='CUBEPROGRAMMER'; VersionState='Known'; Version='2.19.0' }
        Probe=@{ Type='STLINK'; SerialRequested=$false; SerialFound=$false }
        Inventory=@{ State='Known'; Count=1; UnknownSerialCount=0 }
        Target='Unset'; Device=$false; StInfo=$false
    }
}
function Check($facts, $id, $status, $code, $exitCode) {
    $result = Get-DoctorAssessment $facts
    $row = @($result.Findings | Where-Object Id -eq $id)
    Assert ($row.Count -eq 1 -and $row[0].Status -eq $status -and $row[0].Code -eq $code) "Wrong $id finding: $($result | ConvertTo-Json -Depth 6 -Compress)"
    Assert ($result.ExitCode -eq $exitCode) "Wrong exit code for $code"
    Assert ($result.NoticeCode -eq 'McuAndImageNotChecked') 'Missing scope warning'
}
$passport = Get-DoctorPassport
Assert ($passport.schemaVersion -eq 1 -and $passport.baselineRelease -eq '0.3.0') 'Wrong baseline'
Assert ($passport.runtime.powerShell -contains '5.1' -and $passport.runtime.powerShell -contains '7') 'Runtime contract missing'
Assert ($passport.profiles.Count -eq 3) 'Missing hardware profiles'
foreach ($profile in $passport.profiles) {
    Assert ($profile.engine -and $profile.version -and $profile.probe -and $profile.mcu -and $profile.operations.Count -gt 0 -and $profile.evidence -eq 'hardware') 'Incomplete evidence profile'
}
Assert ($passport.evidence.stubCi -match '^https://' -and $passport.evidence.hardware -match '/v0.3.0/') 'Evidence must be pinned separately'
Assert (@($passport.tools.OPENOCD.testedVersions).Count -eq 0) 'Unknown OpenOCD build cannot be exact tested version'
$a = Get-DoctorPassport
$a.tools.JLINK.testedVersions[0]='changed'
Assert ((Get-DoctorPassport).tools.JLINK.testedVersions[0] -eq 'V8.32') 'Passport is mutable shared state'

Check (New-Facts) 'version' 'OK' 'VersionTested' 0
foreach ($version in @('2.23.0','2.18.0','2.19.0+custom')) {
    $f=New-Facts; $f.Engine.Version=$version
    Check $f 'version' 'WARN' 'VersionDifferent' 0
}
$f=New-Facts; $f.Engine.Version='v2.19.0.0'
Check $f 'version' 'OK' 'VersionTested' 0
foreach ($state in @('Unknown','Timeout','Error')) {
    $f=New-Facts; $f.Engine.VersionState=$state
    Check $f 'version' $(if ($state -eq 'Error') {'ERROR'} else {'WARN'}) ('Version'+$state) $(if ($state -eq 'Error') {1} else {0})
    $f=New-Facts; $f.Inventory.State=$state; $f.Inventory.Count=$null; $f.Inventory.UnknownSerialCount=$null; $f.Probe.SerialRequested=$true
    Check $f 'inventory' 'WARN' ('Inventory'+$state) 0
}
foreach ($state in @('Missing','Legacy','Invalid')) {
    $f=New-Facts; $f.Config=$state
    Check $f 'configuration' $(if ($state -eq 'Invalid') {'ERROR'} else {'WARN'}) ('Config'+$state) $(if ($state -eq 'Invalid') {1} else {0})
}
foreach ($state in @('Unsupported','Unknown')) {
    $f=New-Facts; $f.Runtime=$state
    Check $f 'runtime' $(if ($state -eq 'Unsupported') {'ERROR'} else {'WARN'}) ('Runtime'+$state) $(if ($state -eq 'Unsupported') {1} else {0})
}
foreach ($state in @('Missing','NotSelected','Unknown')) {
    $f=New-Facts; $f.Engine.State=$state
    Check $f 'engine' $(if ($state -eq 'Missing') {'ERROR'} else {'WARN'}) ('Engine'+$state) $(if ($state -eq 'Missing') {1} else {0})
}
$f=New-Facts; $f.Inventory.Count=0
Check $f 'inventory' 'ERROR' 'ProbeMissing' 1
$f=New-Facts; $f.Inventory.Count=2
Check $f 'inventory' 'WARN' 'ProbeChoice' 0
$f.Probe.SerialRequested=$true
Check $f 'inventory' 'ERROR' 'SerialMissing' 1
$f.Inventory.UnknownSerialCount=1
Check $f 'inventory' 'WARN' 'SerialUnknown' 0
$f.Probe.SerialFound=$true
Check $f 'inventory' 'OK' 'SerialFound' 0
$f=New-Facts; $f.Engine.Name='OPENOCD'; $f.Engine.Version='0.12.0'; $f.Probe.Type='JLINK'
Check $f 'pair' 'ERROR' 'PairUnsupported' 1
$f.Probe.Type='STLINK'
Check $f 'version' 'WARN' 'VersionDifferent' 0
Check $f 'target' 'WARN' 'TargetUnset' 0
Check $f 'st-info' 'WARN' 'AutoDetectionUnavailable' 0
$f.Target='Missing'
Check $f 'target' 'ERROR' 'TargetMissing' 1
$f.Target='Available'
Check $f 'target' 'OK' 'TargetAvailable' 0
Assert (@((Get-DoctorAssessment $f).Findings | Where-Object Id -eq 'st-info').Count -eq 0) 'Unused helper must not be required'
$f.Target='Unknown'
Check $f 'target' 'WARN' 'TargetUnknown' 0
$f=New-Facts; $f.Engine.Name='JLINK'; $f.Engine.Version='8.32'; $f.Probe.Type='JLINK'
Check $f 'version' 'OK' 'VersionTested' 0
Check $f 'device' 'WARN' 'DeviceUnset' 0
$f.Device=$true
Check $f 'device' 'OK' 'DeviceConfigured' 0
$f.Probe.Type='STLINK'
Check $f 'pair' 'ERROR' 'PairUnsupported' 1
$f=New-Facts; $f.Probe.Type='JLINK'
Check $f 'pair' 'OK' 'PairSupported' 0
$f.Probe.Type=''
Check $f 'pair' 'WARN' 'PairUnknown' 0
$f.Inventory.Count=0
Check $f 'inventory' 'WARN' 'ProbeTypeUnknown' 0
foreach ($mutation in @('missing','state','count','serial','version','engine')) {
    $f=New-Facts
    switch ($mutation) {
        missing { $f.Remove('Config') }
        state { $f.Inventory.State='garbage' }
        count { $f.Inventory.Count=-1 }
        serial { $f.Inventory.UnknownSerialCount=2 }
        version { $f.Engine.Version='' }
        engine { $f.Engine.Name='garbage' }
    }
    $failed=$false
    try { $null=Get-DoctorAssessment $f } catch { $failed=$true }
    Assert $failed "Invalid observation accepted: $mutation"
}
$f=New-Facts; $before=$f | ConvertTo-Json -Depth 6
$one=Get-DoctorAssessment $f; $two=Get-DoctorAssessment $f
Assert (($f | ConvertTo-Json -Depth 6) -ceq $before) 'Policy mutated observations'
Assert (($one | ConvertTo-Json -Depth 6) -ceq ($two | ConvertTo-Json -Depth 6)) 'Policy is not deterministic'
Write-Host 'Doctor passport and pure policy PASS; no collector, CLI or MCU tested.'
