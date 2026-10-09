$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'flash.cmd') -Raw -Encoding UTF8
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Invalid script syntax' }
function Read-Dictionary($name) {
    $nodes = @($ast.FindAll({ param($n)
        $n -is [Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -eq $name
    }, $true))
    if ($nodes.Count -ne 1) { throw "Expected one dictionary: $name" }
    $table = $nodes[0].Right.Find({ param($n) $n -is [Management.Automation.Language.HashtableAst] }, $true)
    if (-not $table) { throw "Missing literal dictionary: $name" }
    # Only evaluate constant data, never execute flash.cmd or discover hardware.
    return $table.SafeGetValue()
}
function Get-Placeholders([string]$text) {
    $pattern = '\{\{|\}\}|\{(?<index>\d+)(?:,-?\d+)?(?::[^{}]*)?\}'
    return (@([regex]::Matches($text, $pattern) | Where-Object { $_.Groups['index'].Success } |
        ForEach-Object { $_.Groups['index'].Value } | Sort-Object -Unique) -join ',')
}
function Assert-Dictionaries($ru, $en) {
    if (@(Compare-Object @($ru.Keys) @($en.Keys)).Count) { throw 'Dictionary key mismatch' }
    foreach ($key in $ru.Keys) {
        foreach ($table in @($ru, $en)) {
            if ($table[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($table[$key])) { throw "Empty translation: $key" }
        }
        if ((Get-Placeholders $ru[$key]) -cne (Get-Placeholders $en[$key])) { throw "Placeholder mismatch: $key" }
    }
}
$ru = Read-Dictionary 'LangRu'
$en = Read-Dictionary 'LangEn'
Assert-Dictionaries $ru $en
$calls = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'T' }, $true)
foreach ($call in $calls) {
    if ($call.CommandElements.Count -gt 1 -and $call.CommandElements[1] -is [Management.Automation.Language.StringConstantExpressionAst]) {
        $key = $call.CommandElements[1].Value
        if (-not $ru.ContainsKey($key) -or -not $en.ContainsKey($key)) { throw "Missing literal T key: $key" }
    }
}
# Mutation controls ensure the validator actually detects each advertised defect.
foreach ($case in @('missing', 'empty', 'placeholder')) {
    $a = @{ Example = 'Value {0}' }; $b = @{ Example = 'Text {0}' }
    switch ($case) {
        missing { $b.Remove('Example'); $b['Other'] = 'Text {0}' }
        empty { $b['Example'] = ' ' }
        placeholder { $b['Example'] = 'Text {1}' }
    }
    $failed = $false
    try { Assert-Dictionaries $a $b } catch { $failed = $true }
    if (-not $failed) { throw "Validator missed $case" }
}
Assert-Dictionaries @{ Example = '{{literal}} {0} {1}' } @{ Example = '{1} {0} {{literal}}' }
Write-Host "Localization passed: $($ru.Count) RU/EN keys, nonempty values, placeholder indices, literal T calls and mutation controls."
