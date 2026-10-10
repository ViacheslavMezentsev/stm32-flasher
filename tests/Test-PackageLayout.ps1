param([string]$PowerShellExe = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $PSScriptRoot ('.tmp-package-' + [guid]::NewGuid().ToString('N'))
$oldOutput = $env:GITHUB_OUTPUT
function Assert($ok, $message) { if (-not $ok) { throw $message } }
try {
    New-Item -ItemType Directory $root | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'bin') -Destination $root -Recurse
    foreach ($name in @('README.md','LICENSE','CHANGELOG.md','CHANGELOG.en.md','docs/TECHNICAL_SPECIFICATION.md','docs/archive/TECHNICAL_SPECIFICATION_INFO_R2.md','docs/reference/stlink-inventory.md','docs/reference/launch-configuration.md','docs/user-guide.md','docs/testing.md')) {
        $destination = Join-Path $root $name
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $destination
    }
    # Execute the actual packaging block, with only GitHub's version expression replaced.
    $workflow = Get-Content (Join-Path $repo '.github/workflows/release.yml') -Raw
    $block = [regex]::Match($workflow, '(?ms)^      - name: Prepare release package\r?\n.*?^        run: \|\r?\n(?<code>(?:          [^\r\n]*\r?\n|\r?\n)+)')
    Assert $block.Success 'Release packaging block not found'
    $code = $block.Groups['code'].Value -replace '(?m)^          ', ''
    $code = $code.Replace('${{ steps.meta.outputs.version }}', '0.0.0')
    Assert (-not $code.Contains('${{')) 'Unresolved workflow expression'
    $env:GITHUB_OUTPUT = Join-Path $root 'outputs.txt'
    Push-Location $root
    try { & ([scriptblock]::Create($code)) } finally { Pop-Location }
    $archive = Join-Path $root 'dist/stm32-flasher-0.0.0.zip'
    $expectedHash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ((Get-Content "$archive.sha256" -Raw) -eq "$expectedHash *stm32-flasher-0.0.0.zip") 'Package checksum mismatch'
    $unpacked = Join-Path $root 'unpacked'
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $commands = @('flash','erase','backup','info','forget','setup','verify')
    Assert (@(Get-ChildItem $unpacked -Filter '*.cmd' -File).Count -eq $commands.Count) 'Missing root commands in ZIP'
    Assert (-not (Test-Path (Join-Path $unpacked 'bin'))) 'ZIP must not require a bin directory'
    foreach ($name in $commands) {
        $entry = Join-Path $unpacked "$name.cmd"
        Assert ((Get-FileHash $entry).Hash -eq (Get-FileHash (Join-Path $repo "bin/$name.cmd")).Hash) "$name changed during packaging"
    }
    $work = Join-Path $root 'firmware directory'
    New-Item -ItemType Directory $work | Out-Null
    foreach ($layout in @('external','copied')) {
        $tool = $unpacked
        if ($layout -eq 'copied') {
            foreach ($name in $commands) { Copy-Item (Join-Path $unpacked "$name.cmd") $work }
            $tool = $work
        }
        Push-Location $work
        try {
            foreach ($name in $commands) {
                foreach ($language in @('ru','en')) {
                    $entry = Join-Path $tool "$name.cmd"
                    $output = & $env:ComSpec /d /c "`"$entry`" --help -Lang $language" 2>&1 | Out-String
                    Assert ($LASTEXITCODE -eq 0 -and $output -match 'stm32-flasher') "$layout $name $language failed: $output"
                }
            }
            Assert (@(Get-ChildItem $work -Force | Where-Object Extension -ne '.cmd').Count -eq 0) 'Help created runtime files'
        } finally { Pop-Location }
    }
    Write-Host 'Release ZIP checksum, unchanged CMD files and portable RU/EN entry points PASS'
} finally {
    $env:GITHUB_OUTPUT = $oldOutput
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($root))) -ne $PSScriptRoot) { throw 'Invalid fixture root' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
