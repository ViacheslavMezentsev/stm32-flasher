param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $repo ('.help-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $source = Get-Content -LiteralPath (Join-Path $repo 'flash.cmd') -Raw -Encoding UTF8
    if ($source -notmatch '\$VERSION\s*=\s*"([^"]+)"') { throw 'Missing script version' }
    $versionLine = 'stm32-flasher ' + $Matches[1]
    # Any fall-through fails before tool discovery, file changes or hardware access.
    $source = $source.Replace('$LangRu = @{', 'throw "HELP_FELL_THROUGH"' + "`r`n" + '$LangRu = @{')
    $source = $source -replace '(?m)^(pwsh|powershell) -NoProfile', ('"' + $PowerShellExe + '" -NoProfile')
    [IO.File]::WriteAllText((Join-Path $fixture 'flash.cmd'), $source, (New-Object Text.UTF8Encoding($false)))
    foreach ($name in @('erase', 'backup', 'forget', 'info')) {
        Copy-Item -LiteralPath (Join-Path $repo "$name.cmd") -Destination $fixture
    }
    Set-Content -LiteralPath (Join-Path $fixture '.flash_engine') -Value 'sentinel'
    Set-Content -LiteralPath (Join-Path $fixture 'firmware.hex') -Value 'sentinel'
    $before = Get-ChildItem $fixture -Force -File | Get-FileHash | ConvertTo-Json
    Push-Location $fixture
    try {
        foreach ($name in @('flash', 'erase', 'backup', 'forget', 'info')) {
            foreach ($key in @('--help', '-Help', '-h', '--version', '-Version')) {
                $output = & $env:ComSpec /d /c "$name.cmd $key -Lang en" 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape($versionLine) -or $output -match 'HELP_FELL_THROUGH') { throw "$name $key failed: $output" }
                if ($key -match 'version') {
                    if ($output.Trim() -ne $versionLine) { throw "Unexpected version output: $output" }
                } elseif ($output -notmatch ([regex]::Escape("$name.cmd [options]"))) { throw "Wrong help: $output" }
            }
        }
        $output = & $env:ComSpec /d /c 'erase.cmd -Backup --help --version -Lang ru' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $output -notmatch 'erase.cmd \[options\]') { throw "Help must precede operation validation: $output" }
    } finally { Pop-Location }
    $after = Get-ChildItem $fixture -Force -File | Get-FileHash | ConvertTo-Json
    if ($before -ne $after) { throw 'Informational commands changed files' }
    Write-Output 'Help/version tests passed.'
} finally {
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -ne $repo) { throw 'Invalid fixture path' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
