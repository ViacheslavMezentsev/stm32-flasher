$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/flash.cmd') -Raw -Encoding UTF8
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Escape-Html', 'Write-HistoryIndex', 'Save-HistoryArtifacts')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Missing function $name" }
    . ([scriptblock]::Create($node.Extent.Text))
}
function T($key) { $key }
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$LangRu = @{ Name = 'ru' }; $ActiveLang = @{ Name = 'en' }
$fixture = Join-Path $PSScriptRoot ('.tmp-history-retention-' + [guid]::NewGuid().ToString('N'))
$failures = @()
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    foreach ($scenario in @('collision', 'navigation', 'limit')) {
        $work = Join-Path $fixture $scenario
        $history = Join-Path $work '.history'
        New-Item -ItemType Directory -Path $history -Force | Out-Null
        $report = Join-Path $work 'report.html'; $log = Join-Path $work 'flash.log'
        try {
            $count = if ($scenario -eq 'limit') { 25 } elseif ($scenario -eq 'collision') { 3 } else { 1 }
            $stamp = '20261009_120000'
            if ($scenario -eq 'collision') {
                # An incomplete older archive must reserve its name too.
                Set-Content (Join-Path $history "flash_$stamp.log") 'orphan sentinel'
            }
            $saved = @()
            for ($i = 0; $i -lt $count; $i++) {
                $time = [DateTimeOffset]::Parse('2026-10-09T12:00:00+00:00').AddMilliseconds($i * 10)
                $tag = if ($scenario -eq 'limit') { $time.AddSeconds($i).ToString('yyyyMMdd_HHmmss') } else { $stamp }
                $entry = [ordered]@{
                    TimestampTag = $tag; TimestampUtc = $time.ToString('o'); TimestampLocal = $time.ToString('yyyy-MM-dd HH:mm:ss zzz')
                    Success = ($i % 2 -eq 0); Operation = 'flash'; ResultText = "result-$i"
                    HexName = "firmware-$i.hex"; EngineName = 'Fixture'; OperationDuration = '00:00:00.010'
                    ReportFile = ''; LogFile = ''
                }
                Set-Content $report "<html><a href='.history/index.html'>History</a><p>session-$i</p></html>" -Encoding UTF8
                Set-Content $log "log-$i" -Encoding UTF8
                Save-HistoryArtifacts $history $log $report $entry
                $saved += [pscustomobject]@{ Report = $entry.ReportFile; Log = $entry.LogFile; Index = $i }
            }
            if ($scenario -eq 'collision') {
                Assert (@(Get-ChildItem $history -Filter 'session_*.json').Count -eq 3) 'Same-second sessions overwritten'
                Assert ((Get-Content (Join-Path $history "flash_$stamp.log")) -eq 'orphan sentinel') 'Incomplete archive overwritten'
            }
            foreach ($item in $saved) {
                Assert ((Get-Content (Join-Path $history $item.Log) -Raw).Trim() -eq "log-$($item.Index)") 'Earlier log overwritten'
                Assert ((Get-Content (Join-Path $history $item.Report) -Raw).Contains("session-$($item.Index)</p>")) 'Earlier report overwritten'
            }
            $index = Get-Content (Join-Path $history 'index.html') -Raw
            if ($scenario -eq 'navigation') {
                $archived = Get-Content (Join-Path $history $saved[0].Report) -Raw
                $href = [regex]::Match($archived, "href='([^']+)'").Groups[1].Value
                Assert (Test-Path -LiteralPath (Join-Path $history $href) -PathType Leaf) 'Archived history link is broken'
                Assert ((Get-Content $report -Raw).Contains("href='.history/index.html'")) 'Root report link changed'
            }
            if ($scenario -eq 'limit') {
                Assert (@(Get-ChildItem $history -Filter 'session_*.json').Count -eq 25) 'Old metadata deleted'
                $links = [regex]::Matches($index, "href='(report_[^']+)'" )
                Assert ($links.Count -eq 20) 'Index limit is not 20'
                for ($j = 0; $j -lt 20; $j++) {
                    Assert ($links[$j].Groups[1].Value -eq $saved[24 - $j].Report) 'Index not sorted newest first'
                }
            }
            foreach ($link in [regex]::Matches($index, "href='([^']+)'")) {
                Assert (Test-Path -LiteralPath (Join-Path $history $link.Groups[1].Value) -PathType Leaf) 'Index link is broken'
            }
            Write-Host "$scenario PASS"
        } catch {
            $failures += "$scenario FAIL: $($_.Exception.Message)"
            Write-Host $failures[-1]
        }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    Assert ($resolved.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Invalid fixture path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Host 'History retention tests passed.'
