<# :
@echo off
chcp 65001 >nul
echo ===================================================
echo   Утилита автоматической прошивки STM32
echo ===================================================

set "SCRIPT_PATH=%~f0"

REM Проверяем наличие pwsh
where pwsh >nul 2>nul
if errorlevel 1 goto use_ps5

:use_pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -Command ". ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath $env:SCRIPT_PATH)))"
goto end

:use_ps5
echo.
echo [!] PowerShell 7 (pwsh) не найден. Пробую Windows PowerShell 5...
powershell -NoProfile -ExecutionPolicy Bypass -Command ". ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath $env:SCRIPT_PATH)))"

:end
pause
exit /b
#>
#Requires -Version 5.1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ══════════════════════════════════════════════════════════════════════════════
#  Вспомогательные функции — вывод
# ══════════════════════════════════════════════════════════════════════════════

function Write-Step($n, $text) { Write-Host "`n$n. $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "   [+] $text" -ForegroundColor Green   }
function Write-Warn($text) { Write-Host "   [!] $text" -ForegroundColor Yellow  }
function Write-Err($text)  { Write-Host "   [X] $text" -ForegroundColor Red     }
function Write-Info($text) { Write-Host "   $text"     -ForegroundColor DarkGray }

function Escape-Html($s) {
    if (-not $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function Md-ToHtml($text) {
    if (-not $text) { return "" }
    $lines = $text -split "`r?`n"
    $html  = @()
    foreach ($line in $lines) {
        $l = $line
        if     ($l -match '^### (.+)') { $html += "<h4>$(Escape-Html $Matches[1])</h4>"; continue }
        elseif ($l -match '^## (.+)')  { $html += "<h3>$(Escape-Html $Matches[1])</h3>"; continue }
        elseif ($l -match '^# (.+)')   { $html += "<h3>$(Escape-Html $Matches[1])</h3>"; continue }
        elseif ($l -match '^---+$')    { $html += "<hr>"; continue }
        elseif ($l.Trim() -eq '')      { $html += ""; continue }
        $l = Escape-Html $l
        $l = $l -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
        $l = $l -replace '\*(.+?)\*',     '<em>$1</em>'
        $l = $l -replace '`(.+?)`',       '<code>$1</code>'
        $l = $l -replace '\[(.+?)\]\((.+?)\)', '<a href="$2" target="_blank">$1</a>'
        if ($line -match '^\s*[-*]\s+') { $html += "<li>$($l -replace '^[-*&\s;]+\s*','')</li>" }
        else                            { $html += "<p>$l</p>" }
    }
    return $html -join "`n"
}

function Status-Row($label, $ok, $okText, $failText) {
    if ($ok) { return "<tr><th>$label</th><td><span class='ok'>&#10003; $okText</span></td></tr>" }
    else     { return "<tr><th>$label</th><td><span class='err'>&#10007; $failText</span></td></tr>" }
}

function Parse-BuildInfo($path) {
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $path)) { return $result }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^\s*-\s+\*\*(.+?)\*\*[:\s]+(.+)$') {
            $result[$Matches[1].Trim(':').Trim()] = $Matches[2].Trim()
        }
    }
    return $result
}

function Get-Stm32Family($deviceIdHex) {
    if (-not $deviceIdHex) { return $null }
    $raw = $deviceIdHex -replace '^0x',''
    try { $id = [Convert]::ToInt64($raw, 16) -band 0xFFF } catch { return $null }

    $table = @{
        0x440="STM32F030x8"; 0x442="STM32F09x"; 0x444="STM32F030x4/6"; 0x445="STM32F04x/F070x6"; 0x448="STM32F07x/F070xB";
        0x410="STM32F10x Med"; 0x412="STM32F10x Low"; 0x414="STM32F10x High"; 0x418="STM32F10x Conn"; 0x420="STM32F10x Med VL"; 0x430="STM32F10x XL";
        0x411="STM32F2xx";
        0x422="STM32F30x"; 0x432="STM32F37x"; 0x438="STM32F334/F328"; 0x439="STM32F302/303 Low"; 0x446="STM32F303 High";
        0x413="STM32F40x/F41x"; 0x419="STM32F42x/F43x"; 0x421="STM32F446"; 0x423="STM32F401xB/C"; 0x431="STM32F411"; 0x433="STM32F401xD/E"; 0x434="STM32F469/F479"; 0x441="STM32F412"; 0x463="STM32F413/F423";
        0x449="STM32F74x/F75x"; 0x451="STM32F76x/F77x"; 0x452="STM32F72x/F73x";
        0x450="STM32H74x/H75x"; 0x480="STM32H7A3/H7B3/H7B0"; 0x483="STM32H72x/H73x";
        0x460="STM32G07x/G08x"; 0x466="STM32G03x/G04x"; 0x467="STM32G0B1/G0C1";
        0x468="STM32G4xx Cat.2"; 0x469="STM32G4xx Cat.3"; 0x479="STM32G4xx Cat.4";
        0x417="STM32L0xx Cat.1"; 0x425="STM32L0xx Cat.2"; 0x447="STM32L0xx Cat.5"; 0x457="STM32L011";
        0x415="STM32L476/L486"; 0x435="STM32L43x/L44x"; 0x461="STM32L496/L4A6"; 0x462="STM32L45x/L46x"; 0x464="STM32L412/L422"; 0x470="STM32L4R/L4S";
        0x482="STM32U575/U585"; 0x4B5="STM32U5A5/U5A9";
        0x492="STM32WB55"; 0x495="STM32WB50"; 0x497="STM32WL5x"
    }

    if ($table.ContainsKey($id)) { return $table[$id] }
    return "STM32 (Device ID 0x$($id.ToString('X3')))"
}

function Invoke-Download($url, $outFile) {
    try { Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop; return } catch {}
    try { $wc = [System.Net.WebClient]::new(); $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy(); $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials; $wc.DownloadFile($url, $outFile); return } catch {}
    try { Start-BitsTransfer -Source $url -Destination $outFile -ErrorAction Stop; return } catch {}
    throw "Все методы загрузки не удались.`nСкачайте OpenOCD вручную: $url`nРаспакуйте в: $ToolDir"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Пути и окружение
# ══════════════════════════════════════════════════════════════════════════════

$CurrentDir     = if ($env:SCRIPT_PATH) { Split-Path -Parent $env:SCRIPT_PATH } else { $PSScriptRoot }
$ToolDir        = Join-Path $CurrentDir ".tools"
$LogFile        = Join-Path $CurrentDir "flash_log.txt"
$HtmlReport     = Join-Path $CurrentDir "report.html"

$OpenOcdUrl     = "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-3/xpack-openocd-0.12.0-3-win32-x64.zip"
$OpenOcdZip     = Join-Path $ToolDir "openocd.zip"
$OpenOcdExe     = Join-Path $ToolDir "xpack-openocd-0.12.0-3\bin\openocd.exe"

$PsVerStr = $PSVersionTable.PSVersion.ToString()
$WinInfo = ""
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue; if ($os) { $WinInfo = "$($os.Caption) (Build $($os.BuildNumber))" } } catch {}
if (-not $WinInfo) { $WinInfo = [System.Environment]::OSVersion.VersionString }

# ══════════════════════════════════════════════════════════════════════════════
#  1. Выбор .hex
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "1" "Поиск файлов прошивки..."
$HexFiles = @(Get-ChildItem -LiteralPath $CurrentDir -Filter "*.hex" -ErrorAction SilentlyContinue)

if ($HexFiles.Count -eq 0) { Write-Err "Файлы .hex не найдены!"; Start-Sleep -Seconds 3; exit 1 }

Write-Host "   Доступные прошивки:"
$i = 1; foreach ($f in $HexFiles) { Write-Host "     [$i] $($f.Name)"; $i++ }
$choice = Read-Host "`n   Выберите номер прошивки"
$idx = [int]$choice - 1
if ($idx -lt 0 -or $idx -ge $HexFiles.Count) { Write-Err "Неверный выбор."; Start-Sleep -Seconds 3; exit 1 }

$TargetHex = $HexFiles[$idx].FullName
$HexName   = $HexFiles[$idx].Name
Write-Info "Выбрано: $HexName"
$BuildType = if ($HexName -match 'Debug') { "Debug" } elseif ($HexName -match 'Release') { "Release" } else { "Unknown" }

# ══════════════════════════════════════════════════════════════════════════════
#  2. Build Info + CHANGELOG
# ══════════════════════════════════════════════════════════════════════════════

$BuildInfoPath = Join-Path $CurrentDir "build_info_$BuildType.md"
$BuildInfo     = Parse-BuildInfo $BuildInfoPath
$ChangelogPath = Join-Path $CurrentDir "CHANGELOG.md"
$ChangelogContent = if (Test-Path -LiteralPath $ChangelogPath) { Get-Content -LiteralPath $ChangelogPath -Raw -Encoding UTF8 } else { "" }

# ══════════════════════════════════════════════════════════════════════════════
#  3. Выбор движка (STM32CubeProgrammer vs OpenOCD)
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "2" "Определение движка прошивки..."

$EngineCfgPath = Join-Path $CurrentDir ".flash_engine"
$SelectedEngine = ""

if (Test-Path -LiteralPath $EngineCfgPath) {
    $SavedEngine = (Get-Content -LiteralPath $EngineCfgPath -TotalCount 1).Trim()
    if ($SavedEngine -eq "OPENOCD" -or (Test-Path -LiteralPath $SavedEngine)) {
        $SelectedEngine = $SavedEngine
    }
}

if (-not $SelectedEngine) {
    Write-Info "Поиск STM32CubeProgrammer..."
    $SearchPaths = @(
        "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\ST\STM32CubeCLT*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\ST\STM32CubeIDE*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "$env:LOCALAPPDATA\Programs\STM32CubeCLT*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    )
    $FoundCli = @()
    foreach ($p in $SearchPaths) {
        $found = Get-Item -Path $p -ErrorAction SilentlyContinue
        if ($found) { $FoundCli += $found.FullName }
    }
    $FoundCli = $FoundCli | Select-Object -Unique

    $Opts = @()
    $Opts += @{ Label = "OpenOCD (Встроенный/Автоматический)"; Value = "OPENOCD" }
    foreach ($cli in $FoundCli) { $Opts += @{ Label = "CubeProgrammer ($cli)"; Value = $cli } }

    if ($Opts.Count -eq 1) {
        $SelectedEngine = "OPENOCD"
    } else {
        Write-Host "   Найдено несколько утилит прошивки:" -ForegroundColor Yellow
        for ($k=0; $k -lt $Opts.Count; $k++) { Write-Host "     [$($k+1)] $($Opts[$k].Label)" }
        $ans = Read-Host "   Выберите утилиту (рекомендуется CubeProgrammer)"
        $idx = [int]$ans - 1
        if ($idx -ge 0 -and $idx -lt $Opts.Count) { $SelectedEngine = $Opts[$idx].Value } else { $SelectedEngine = "OPENOCD" }
    }
    try { Set-Content -LiteralPath $EngineCfgPath -Value $SelectedEngine -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

# ══════════════════════════════════════════════════════════════════════════════
#  4. Подготовка и Прошивка
# ══════════════════════════════════════════════════════════════════════════════

$LogStd = "$LogFile.stdout"
$LogErr = "$LogFile.stderr"
$ExePath = ""
$ExeArgs = @()

if ($SelectedEngine -eq "OPENOCD") {
    Write-Step "3" "Подготовка OpenOCD..."
    if (-Not (Test-Path -LiteralPath $OpenOcdExe)) {
        Write-Warn "Скачивание OpenOCD с GitHub (~5 MB)..."
        New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
        Invoke-Download $OpenOcdUrl $OpenOcdZip
        Expand-Archive -Path $OpenOcdZip -DestinationPath $ToolDir -Force
        Remove-Item -LiteralPath $OpenOcdZip -ErrorAction SilentlyContinue
    }
    $OpenOcdScripts = Join-Path $ToolDir "xpack-openocd-0.12.0-3\openocd\scripts"
    if (-Not (Test-Path -LiteralPath $OpenOcdScripts)) {
        $foundS = Get-ChildItem -Path (Join-Path $ToolDir "xpack-openocd-0.12.0-3") -Recurse -Filter "stlink.cfg" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundS) { $OpenOcdScripts = Split-Path -Parent $foundS.DirectoryName }
    }

    # Поиск TargetCfg
    $TargetCfg = ""
    $SavedTargetCfg = Join-Path $CurrentDir ".openocd_target"
    if (Test-Path -LiteralPath $SavedTargetCfg) { $TargetCfg = (Get-Content -LiteralPath $SavedTargetCfg -TotalCount 1).Trim() }
    
    if (-not $TargetCfg) {
        $Roots = @( $CurrentDir, (Split-Path $CurrentDir -Parent -ErrorAction SilentlyContinue), (Split-Path (Split-Path $CurrentDir -Parent -ErrorAction SilentlyContinue) -Parent -ErrorAction SilentlyContinue) ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($r in $Roots) {
            $ioc = Get-ChildItem -Path $r -Filter "*.ioc" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ioc) {
                if ((Get-Content -LiteralPath $ioc.FullName -ErrorAction SilentlyContinue) -match "^Mcu\.Family=STM32(.+)$") {
                    $TargetCfg = "target/stm32$($Matches[1].ToLower())x.cfg"; Write-Info "Таргет найден в .ioc"; break
                }
            }
        }
    }
    if (-not $TargetCfg) {
        if ($HexName -match "(?i)stm32([fghlu]\d)") { $TargetCfg = "target/stm32$($Matches[1].ToLower())x.cfg" }
    }
    if (-not $TargetCfg) {
        Write-Host "   [?] Не удалось определить семейство. Введите название cfg (например target/stm32f4x.cfg):" -ForegroundColor Yellow -NoNewline
        $TargetCfg = Read-Host
    }
    try { Set-Content -LiteralPath $SavedTargetCfg -Value $TargetCfg -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}

    Write-Host "   Движок: OpenOCD (Конфиг: $TargetCfg)" -ForegroundColor Cyan
    $ExePath = $OpenOcdExe
    $TclCmd = "`"program {$TargetHex} verify reset exit`""
    $ExeArgs = @("-s", "`"$OpenOcdScripts`"", "-f", "interface/stlink.cfg", "-f", $TargetCfg, "-c", $TclCmd)

} else {
    Write-Step "3" "Подготовка CubeProgrammer..."
    Write-Host "   Движок: STM32CubeProgrammer" -ForegroundColor Cyan
    Write-Info "Автоопределение семейства микроконтроллера включено (через DAP)."
    $ExePath = $SelectedEngine
    # Ключи: -c port=SWD (подключение), -w (прошивка), -v (верификация), -rst (сброс)
    $ExeArgs = @("-c", "port=SWD", "-w", $TargetHex, "-v", "-rst")
}

Write-Host "   Прошивка... Пожалуйста, подождите 10-15 секунд."

$process = Start-Process -FilePath $ExePath -ArgumentList $ExeArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $LogStd -RedirectStandardError $LogErr

$stdout     = Get-Content -LiteralPath $LogStd -Raw -ErrorAction SilentlyContinue
$stderr     = Get-Content -LiteralPath $LogErr -Raw -ErrorAction SilentlyContinue
$LogContent = @($stdout, $stderr | Where-Object { $_ }) -join "`n"

Remove-Item -LiteralPath $LogStd, $LogErr -ErrorAction SilentlyContinue
$LogContent | Set-Content -LiteralPath $LogFile -Encoding UTF8

# ══════════════════════════════════════════════════════════════════════════════
#  5. Парсинг лога (Универсальный)
# ══════════════════════════════════════════════════════════════════════════════

$ExitOk = $process.ExitCode -eq 0
$IsStlinkFound = $false; $IsProgrammed = $false; $IsVerified = $false
$ToolInfo = ""; $StlinkInfo = ""; $TargetVoltage = ""; $McuCore = ""; $McuDevId = ""; $McuDevIdHex = ""; $McuFlash = ""; $McuFamily = ""

if ($SelectedEngine -eq "OPENOCD") {
    $IsStlinkFound = $LogContent -match "target voltage"
    $IsProgrammed  = $LogContent -match "\*\* Programming Finished \*\*"
    $IsVerified    = $LogContent -match "\*\* Verified OK \*\*"
    
    if ($LogContent -match '(?m)^((?:xPack )?Open On-Chip Debugger[^\r\n]+)') { $ToolInfo = $Matches[1].Trim() }
    if ($LogContent -match 'Info\s*:\s*(STLINK[^\r\n]+)') { $StlinkInfo = $Matches[1].Trim() }
    if ($LogContent -match 'target voltage[^:]*:\s*([\d.]+)') { $TargetVoltage = "$($Matches[1]) V" }
    if ($LogContent -match 'Info\s*:\s*(\S+\.cpu[:\s]+Cortex[^\r\n]+)') { $McuCore = $Matches[1].Trim() }
    if ($LogContent -match 'device id(?:code)?\s*=\s*(0x[\da-fA-F]+)') { $McuDevIdHex = $Matches[1]; $McuDevId = $McuDevIdHex }
    if ($LogContent -match 'flash size\s*=\s*([\d]+\s*KiB)') { $McuFlash = $Matches[1] }
    $McuFamily = Get-Stm32Family $McuDevIdHex
} else {
    # STM32CubeProgrammer парсинг
    $IsStlinkFound = ($LogContent -match "ST-LINK SN" -or $LogContent -match "Voltage")
    $IsProgrammed  = $LogContent -match "File download complete"
    $IsVerified    = $LogContent -match "Download verified successfully"

    if ($LogContent -match 'STM32CubeProgrammer\s+(v[\d\.]+)') { $ToolInfo = "STM32CubeProgrammer " + $Matches[1] }
    if ($LogContent -match 'ST-LINK FW\s*:\s*([^\r\n]+)') { $StlinkInfo = $Matches[1].Trim() }
    if ($LogContent -match 'Voltage\s*:\s*([^\r\n]+)') { $TargetVoltage = $Matches[1].Trim() }
    if ($LogContent -match 'Device CPU\s*:\s*([^\r\n]+)') { $McuCore = $Matches[1].Trim() }
    if ($LogContent -match 'Device ID\s*:\s*(0x[\da-fA-F]+)') { $McuDevIdHex = $Matches[1]; $McuDevId = $McuDevIdHex }
    if ($LogContent -match 'Flash size\s*:\s*([^\r\n]+)') { $McuFlash = $Matches[1].Trim() }
    if ($LogContent -match 'Device name\s*:\s*([^\r\n]+)') { $McuFamily = $Matches[1].Trim() } else { $McuFamily = Get-Stm32Family $McuDevIdHex }
}

$Success = $IsStlinkFound -and $IsProgrammed -and $IsVerified -and $ExitOk

if ($Success) {
    Write-Ok "УСПЕШНО! Прошивка загружена и проверена."
} else {
    Write-Err "Что-то пошло не так. Exit code: $($process.ExitCode)"
    Write-Info "Открываю отчёт..."
}

# ══════════════════════════════════════════════════════════════════════════════
#  6. HTML-отчёт
# ══════════════════════════════════════════════════════════════════════════════

$Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ResultBg   = if ($Success) { "#d1f0de" } else { "#fde8e8" }
$ResultFg   = if ($Success) { "#0f5c2e" } else { "#7a1c1c" }
$ResultIcon = if ($Success) { "&#10003;" } else { "&#10007;" }
$ResultMsg  = if ($Success) { "Прошивка завершена успешно" } else { "Ошибка прошивки — см. детали и лог ниже" }

$BadgeBg    = switch ($BuildType) { "Release" { "#0d6efd" } "Debug" { "#fd7e14" } default { "#6c757d" } }
$HexNameEsc = Escape-Html $HexName

$LabelMap = [ordered]@{ "Firmware Version"="Версия прошивки"; "Stamp"="Метка сборки"; "Integrity"="Целостность (CRC32)"; "Project"="Проект"; "System"="HAL / SDK"; "Compiler"="Компилятор"; "Build Type"="Тип сборки"; "Branch"="Ветка Git"; "Author"="Автор"; "Commit Message"="Коммит"; "Commit Link"="Ссылка на коммит"; "Releases Page"="Страница релизов" }
$BiRows = ""
foreach ($key in $BuildInfo.Keys) {
    $label = if ($LabelMap[$key]) { $LabelMap[$key] } else { Escape-Html $key }
    $val = $BuildInfo[$key] -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2" target="_blank">$1</a>' -replace '(?<!href=")(https?://[^\s<>"]+)', '<a href="$1" target="_blank">$1</a>'
    $BiRows += "<tr><th>$label</th><td>$val</td></tr>`n"
}
$BuildInfoSection = if ($BiRows) { "<div class='card'><h2>&#128196; Сборка ($BuildType)</h2><table>$BiRows</table></div>" } else { "" }

$ChangelogSection = ""
if ($ChangelogContent) {
    $ChangelogHtml = Md-ToHtml $ChangelogContent
    $ChangelogPathUrl = "file:///$($ChangelogPath -replace '\\','/')"
    $ChangelogSection = "<div class='card'><h2>&#128221; История изменений (CHANGELOG)</h2><div class='changelog-box'>$ChangelogHtml</div><p class='changelog-footer'>Источник: <a href='$ChangelogPathUrl' target='_blank'>CHANGELOG.md</a></p></div>"
}

$EnvTool   = if ($ToolInfo)       { Escape-Html $ToolInfo }        else { "<em class='na'>не удалось определить</em>" }
$EnvStlink = if ($StlinkInfo)     { Escape-Html $StlinkInfo }      else { "<em class='na'>не обнаружен</em>" }
$EnvVolt   = if ($TargetVoltage)  { "<strong>$(Escape-Html $TargetVoltage)</strong>" } else { "<em class='na'>—</em>" }
$EnvCore   = if ($McuCore)        { Escape-Html $McuCore }         else { "<em class='na'>—</em>" }
$EnvFamily = if ($McuFamily)      { "<strong>$(Escape-Html $McuFamily)</strong>" }    else { "<em class='na'>—</em>" }
$EnvDevId  = if ($McuDevId)       { "<code>$(Escape-Html $McuDevId)</code>" }         else { "<em class='na'>—</em>" }
$EnvFlash  = if ($McuFlash)       { Escape-Html $McuFlash }        else { "<em class='na'>—</em>" }
$EnvWin    = Escape-Html $WinInfo
$EnvPs     = Escape-Html $PsVerStr

$LogHtml = Escape-Html $LogContent
$ProjectTitle = if ($BuildInfo["Project"]) { Escape-Html $BuildInfo["Project"] } else { Escape-Html ($HexName -replace '\.hex$','') }

$HtmlContent = @"
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Flash Report — $ProjectTitle</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', system-ui, Arial, sans-serif; background: #eef0f4; color: #212529; padding: 28px 36px; }
    .page-header { display: flex; align-items: baseline; gap: 12px; margin-bottom: 4px; flex-wrap: wrap; }
    .page-header h1 { font-size: 1.3rem; font-weight: 700; }
    .badge { padding: 2px 10px; border-radius: 20px; font-size: .72rem; font-weight: 700; color: #fff; background: $BadgeBg; white-space: nowrap; align-self: center; }
    .sub { color: #868e96; font-size: .82rem; margin-bottom: 20px; }
    .result-banner { display: flex; align-items: center; gap: 10px; background: $ResultBg; color: $ResultFg; border-radius: 10px; padding: 13px 20px; font-size: 1.05rem; font-weight: 700; margin-bottom: 18px; }
    .result-banner .ico { font-size: 1.3rem; line-height: 1; }
    .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; }
    .card { background: #fff; border-radius: 10px; box-shadow: 0 1px 4px rgba(0,0,0,.09); padding: 18px 22px; margin-bottom: 16px; }
    h2 { font-size: .93rem; font-weight: 700; color: #343a40; margin-bottom: 12px; }
    table { width: 100%; border-collapse: collapse; font-size: .86rem; }
    th, td { padding: 7px 10px; text-align: left; border-bottom: 1px solid #f0f0f0; vertical-align: top; }
    th { background: #f8f9fa; font-weight: 600; color: #495057; white-space: nowrap; width: 44%; }
    tr:last-child th, tr:last-child td { border-bottom: none; }
    .sh th { background: #e9ecef !important; color: #6c757d; font-size: .75rem; letter-spacing: .06em; text-transform: uppercase; }
    .ok   { color: #198754; font-weight: 600; }
    .err  { color: #dc3545; font-weight: 600; }
    .warn { color: #856404; font-weight: 500; }
    .na   { color: #adb5bd; font-style: italic; }
    code  { background: #f1f3f5; padding: 1px 5px; border-radius: 3px; font-size: .82rem; font-family: 'Consolas', monospace; }
    a     { color: #0d6efd; text-decoration: none; }
    a:hover { text-decoration: underline; }
    pre   { background: #1a1a2e; color: #cdd3de; padding: 14px 16px; border-radius: 8px; font-size: .74rem; line-height: 1.55; font-family: 'Consolas', monospace; white-space: pre-wrap; word-break: break-all; max-height: 360px; overflow-y: auto; }
    .changelog-box { max-height: 320px; overflow-y: auto; padding: 12px 16px; background: #f8f9fa; border: 1px solid #e9ecef; border-radius: 6px; font-size: .84rem; line-height: 1.7; }
    .changelog-box h3, .changelog-box h4 { margin: 10px 0 3px; font-size: .9rem; }
    .changelog-box p  { margin: 3px 0; }
    .changelog-box li { margin-left: 18px; margin-bottom: 2px; }
    .changelog-box code { background: #dee2e6; }
    .changelog-box hr  { border: none; border-top: 1px solid #dee2e6; margin: 8px 0; }
    .changelog-footer  { margin-top: 8px; font-size: .78rem; color: #868e96; }
    @media (max-width: 680px) { .grid2 { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="page-header">
    <h1>&#128268; Flash Report — $ProjectTitle</h1>
    <span class="badge">$HexNameEsc</span>
  </div>
  <p class="sub">$Timestamp</p>
  <div class="result-banner"><span class="ico">$ResultIcon</span><span>$ResultMsg</span></div>
  <div class="grid2">
    <div class="card">
      <h2>&#9745; Статус этапов</h2>
      <table>
        $(Status-Row "ST-Link обнаружен"  $IsStlinkFound "Да"        "Нет — проверьте USB и питание")
        $(Status-Row "Запись во Flash"    $IsProgrammed  "Завершена" "Ошибка записи")
        $(Status-Row "Верификация"        $IsVerified    "Пройдена"  "Провалена")
        $(Status-Row "Код выхода утилиты" $ExitOk        "0 (успех)" "$($process.ExitCode) (ошибка)")
      </table>
    </div>
$BuildInfoSection
  </div>
  <div class="card">
    <h2>&#128187; Схема прошивки</h2>
    <table>
      <tr class="sh"><th colspan="2">Хост</th></tr>
      <tr><th>Операционная система</th><td>$EnvWin</td></tr>
      <tr><th>PowerShell</th><td>$EnvPs</td></tr>
      <tr><th>Движок прошивки</th><td>$EnvTool</td></tr>
      <tr class="sh"><th colspan="2">Программатор</th></tr>
      <tr><th>ST-Link</th><td>$EnvStlink</td></tr>
      <tr><th>Напряжение питания МК</th><td>$EnvVolt</td></tr>
      <tr class="sh"><th colspan="2">Микроконтроллер</th></tr>
      <tr><th>Семейство</th><td>$EnvFamily</td></tr>
      <tr><th>Ядро / Процессор</th><td>$EnvCore</td></tr>
      <tr><th>Device ID</th><td>$EnvDevId</td></tr>
      <tr><th>Flash</th><td>$EnvFlash</td></tr>
    </table>
  </div>
$ChangelogSection
  <div class="card">
    <h2>&#128220; Вывод утилиты</h2>
    <pre>$LogHtml</pre>
  </div>
</body>
</html>
"@

Set-Content -LiteralPath $HtmlReport -Value $HtmlContent -Encoding UTF8
Invoke-Item $HtmlReport