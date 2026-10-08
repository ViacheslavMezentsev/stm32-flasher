param([string]$Scenario = '')
# TC-22: real child processes, no installed probe tools or hardware.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$hostExe = (Get-Process -Id $PID).Path
$root = Join-Path $PSScriptRoot ('.tmp-inventory-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$fakeExe = Join-Path $root 'inventory-fixture.exe'
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Stop-FixtureProcesses {
    foreach ($file in @(Get-ChildItem $root -Filter '*.pid')) {
        $processId = [int](Get-Content $file.FullName -Raw)
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process -and $process.Path -eq $fakeExe) {
            $process.Kill()
            Assert ($process.WaitForExit(5000)) 'Fixture cleanup timed out'
        }
        Remove-Item -LiteralPath $file.FullName
    }
}
$helper = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class Fixture {
    public static void Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("TC_ROOT");
        bool hold = args.Length > 0 && args[0] == "hold";
        File.WriteAllText(Path.Combine(root, hold ? "hold.pid" : "tool.pid"), Process.GetCurrentProcess().Id.ToString());
        string mode = Environment.GetEnvironmentVariable("TC_MODE");
        if (hold || mode == "hang") { Thread.Sleep(120000); return; }
        if (mode.StartsWith("pipe")) {
            var start = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, "hold");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardOutput = mode == "pipeerr";
            start.RedirectStandardError = mode == "pipeout";
            var child = Process.Start(start);
            File.WriteAllText(Path.Combine(root, "hold.pid"), child.Id.ToString());
        } else {
            Console.Out.WriteLine(new string('O', 131072));
            Console.Error.WriteLine(new string('E', 131072));
        }
        Console.WriteLine("SEGGER J-Link Commander V1.00");
        Console.WriteLine("J-Link[0]: Serial number: 12345678, ProductName: Test probe");
    }
}
'@
$worker = @'
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput((Get-Content $env:TC_SOURCE -Raw -Encoding UTF8), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Invoke-ProbeInventory','Get-JLinkProbes','ConvertFrom-JLinkProbeList')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Find-JLinkExe { return $env:TC_EXE }
function T($key) { return $key }
$watch = [Diagnostics.Stopwatch]::StartNew()
$result = $null; $failure = ''
try {
    if ($env:TC_KIND -eq 'cube') { $result = Invoke-ProbeInventory $env:TC_EXE '--help' }
    else { $result = @(Get-JLinkProbes) }
} catch { $failure = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
$watch.Stop()
@{ Elapsed=$watch.Elapsed.TotalSeconds; Result=$result; Failure=$failure } |
    ConvertTo-Json -Depth 4 -Compress | Set-Content (Join-Path $env:TC_ROOT 'result.json') -Encoding UTF8
'@
try {
    Set-Content (Join-Path $root 'fixture.cs') $helper -Encoding ASCII
    Set-Content (Join-Path $root 'compile.ps1') 'Add-Type -Path (Join-Path $PSScriptRoot "fixture.cs") -OutputAssembly (Join-Path $PSScriptRoot "inventory-fixture.exe") -OutputType ConsoleApplication -ErrorAction Stop' -Encoding ASCII
    # Windows PowerShell targets the installed .NET Framework, also runnable from PS7.
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'compile.ps1')
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path $fakeExe)) 'Fixture compilation failed'
    Set-Content (Join-Path $root 'worker.ps1') $worker -Encoding ASCII
    $cases = @('cube-flood','jlink-flood','cube-hang','jlink-hang','cube-pipe','jlink-pipe',
        'cube-pipeout','jlink-pipeout','cube-pipeerr','jlink-pipeerr')
    if ($Scenario) { Assert ($Scenario -in $cases) 'Unknown scenario'; $cases = @($Scenario) }
    foreach ($case in $cases) {
        $kind, $mode = $case.Split('-')
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $hostExe
        $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'worker.ps1') + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.EnvironmentVariables['TC_ROOT'] = $root
        $start.EnvironmentVariables['TC_SOURCE'] = Join-Path $repo 'flash.cmd'
        $start.EnvironmentVariables['TC_EXE'] = $fakeExe
        $start.EnvironmentVariables['TC_KIND'] = $kind
        $start.EnvironmentVariables['TC_MODE'] = $mode
        $workerProcess = New-Object Diagnostics.Process
        $workerProcess.StartInfo = $start
        try {
            [void]$workerProcess.Start()
            Assert ($workerProcess.WaitForExit(20000)) "$case exceeded watchdog (20 s)"
            Assert ($workerProcess.ExitCode -eq 0) "$case worker failed"
            $result = Get-Content (Join-Path $root 'result.json') -Raw | ConvertFrom-Json
            if ($mode -eq 'flood') {
                Assert (-not $result.Failure) "$case unexpected failure: $($result.Failure)"
                if ($kind -eq 'cube') { Assert ($result.Result -match 'O{131072}' -and $result.Result -match 'E{131072}') 'Lost stdout/stderr' }
                else { Assert (@($result.Result).Count -eq 1 -and $result.Result[0].Serial -eq '12345678') 'J-Link parsing failed' }
            } else {
                if ($kind -eq 'cube') { Assert ($null -eq $result.Result -and -not $result.Failure) "$case did not report unavailable" }
                else { Assert ($result.Failure -eq 'TimeoutException:JLinkTimeout') "$case missing timeout: $($result.Failure)" }
                if ($mode -eq 'hang') {
                    Assert ($result.Elapsed -ge 9 -and $result.Elapsed -lt 17) "$case unexpected wait: $($result.Elapsed)"
                    $tool = Get-Process -Id ([int](Get-Content (Join-Path $root 'tool.pid') -Raw)) -ErrorAction SilentlyContinue
                    Assert (-not $tool -or $tool.Path -ne $fakeExe) "$case failed to stop tool"
                } else {
                    Assert ($result.Elapsed -lt 8) "$case unbounded output drain: $($result.Elapsed)"
                    Assert (Test-Path (Join-Path $root 'hold.pid')) 'Pipe holder was not started'
                }
            }
            Write-Host "$case PASS ($([Math]::Round($result.Elapsed, 2)) s)"
        } finally {
            if (-not $workerProcess.HasExited) { $workerProcess.Kill(); [void]$workerProcess.WaitForExit(5000) }
            $workerProcess.Dispose()
            Stop-FixtureProcesses
        }
    }
} finally {
    Stop-FixtureProcesses
    $resolved = [IO.Path]::GetFullPath($root)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Inventory timeout tests passed without hardware.'
