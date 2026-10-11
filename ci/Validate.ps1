param([string]$PythonExe = 'python')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    $required = @(
        'bin/flash.cmd', 'bin/erase.cmd', 'bin/forget.cmd', 'bin/backup.cmd',
        'bin/info.cmd', 'bin/setup.cmd', 'bin/check.cmd', 'bin/halt.cmd',
        'bin/go.cmd', 'bin/reset.cmd', 'README.md', 'README.en.md', 'LICENSE',
        'CHANGELOG.md', 'CHANGELOG.en.md', 'AGENTS.md', 'TODO.md',
        'ci/README.md', 'ci/README.en.md', 'ci/Invoke-Local.ps1',
        'tests/Invoke-Tests.ps1', 'tests/tools/check_spec.py',
        'docs/TECHNICAL_SPECIFICATION.md', 'docs/archive/TECHNICAL_SPECIFICATION_INFO_R2.md',
        'docs/reference/stlink-inventory.md', 'docs/reference/launch-configuration.md',
        'docs/user-guide.md', 'docs/testing.md'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) { throw "Missing required files: $($missing -join ', ')" }
    $files = @(Get-Item bin/flash.cmd) + @(Get-ChildItem tests,ci -Filter '*.ps1' -File)
    foreach ($file in $files) {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput(
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8),
            [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count) { throw "Syntax errors in $($file.Name): $($errors | Out-String)" }
    }
    $content = Get-Content bin/flash.cmd -Raw -Encoding UTF8
    if ($content -notmatch '\$VERSION\s*=\s*"(\d+\.\d+\.\d+)"') {
        throw 'Version must use Major.Minor.Patch.'
    }
    Write-Host "Script version: $($Matches[1]); syntax checked: $($files.Count) files"
    foreach ($name in @('CHANGELOG.md', 'CHANGELOG.en.md')) {
        $text = Get-Content $name -Raw -Encoding UTF8
        foreach ($heading in [regex]::Matches($text, '(?m)^### (.+)\r?$')) {
            if ($heading.Groups[1].Value.Trim() -notin @('Добавлено','Изменено','Исправлено','Added','Changed','Fixed')) {
                throw "Unexpected changelog category in ${name}: $($heading.Value)"
            }
        }
    }
    & $PythonExe -X utf8 tests/tools/check_spec.py docs/TECHNICAL_SPECIFICATION.md --strict
    if ($LASTEXITCODE -ne 0) { throw "Specification check failed: $LASTEXITCODE" }
} finally { Pop-Location }
