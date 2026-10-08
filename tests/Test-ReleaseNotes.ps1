$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem (Join-Path $repo 'docs/releases') -Filter 'v*.md' -File)
if (-not $files.Count) { throw 'No versioned release notes found' }
foreach ($file in $files) {
    if ($file.BaseName -notmatch '^v(\d+\.\d+\.\d+)$') { throw "Invalid release note name: $($file.Name)" }
    $version = $Matches[1]
    $body = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $sections = [regex]::Match($body, '(?s)\A(?<ru>.+?)<details>\s*<summary>English</summary>\s*(?<en>.+?)\s*</details>\s*\z')
    if (-not $sections.Success) { throw "Missing RU / collapsed English structure: $($file.Name)" }
    if ($sections.Groups['ru'].Value -notmatch '[\u0400-\u04FF]') { throw "Missing Russian text: $($file.Name)" }
    foreach ($language in @('ru', 'en')) {
        $text = $sections.Groups[$language].Value
        if (-not $text.Contains("stm32-flasher $version")) { throw "Version heading mismatch: $($file.Name) $language" }
        $changelog = if ($language -eq 'ru') { 'CHANGELOG.md' } else { 'CHANGELOG.en.md' }
        $link = "https://github.com/ViacheslavMezentsev/stm32-flasher/blob/v$version/$changelog"
        if (-not $text.Contains("($link)")) { throw "Missing tag-pinned changelog link: $($file.Name) $language" }
    }
    foreach ($link in [regex]::Matches($body, '\]\(([^)]+)\)')) {
        if ($link.Groups[1].Value -notmatch '^https://') { throw "Release page requires absolute links: $($file.Name)" }
    }
    Write-Host "$($file.Name): bilingual release notes PASS"
}
