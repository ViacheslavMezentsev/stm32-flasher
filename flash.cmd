<# :
@echo off
setlocal
chcp 65001 >nul
set "SCRIPT_PATH=%~f0"
set "FLASH_HELP="
set "FLASH_VERSION="
:scan_reference_args
if "%~1"=="" goto launch
if /i "%~1"=="--help" set "FLASH_HELP=1"
if /i "%~1"=="-Help" set "FLASH_HELP=1"
if /i "%~1"=="-h" set "FLASH_HELP=1"
if /i "%~1"=="--version" set "FLASH_VERSION=1"
if /i "%~1"=="-Version" set "FLASH_VERSION=1"
shift
goto scan_reference_args
:launch

REM Launch PowerShell with UTF-8 encoded script text
where pwsh >nul 2>nul
if errorlevel 1 goto use_ps5

:use_pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -Command ". ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath $env:SCRIPT_PATH)))" %*
goto end

:use_ps5
powershell -NoProfile -ExecutionPolicy Bypass -Command ". ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath $env:SCRIPT_PATH)))" %*

:end
exit /b
#>
param(
    [string]$Input = "",
    [string]$Lang = "",
    [string]$HexFile = "",
    [string]$Engine = "",
    [string]$Target = "",
    [string]$Device = "",
    [string]$Probe = "",
    [string]$Serial = "",
    [string]$Sha256 = "",
    [switch]$Erase,
    [switch]$ResetConfig,
    [switch]$Clean,
    [switch]$Backup,
    [switch]$Info,
    [switch]$ProbeTarget,
    [string]$Output = "",
    [string]$Address = "",
    [string]$Size = "",
    [Alias('h', '-help')][switch]$Help,
    [Alias('Version', '-version')][switch]$ShowVersion,
    [switch]$Silent,
    [switch]$DryRun
)

#Requires -Version 5.1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Версия скрипта
$VERSION = "0.2.9"

# Informational requests must exit before settings, discovery or any operation.
$referenceArgs = @($Input) + @($args)
$helpRequested = $Help -or $env:FLASH_HELP -eq '1' -or ($referenceArgs -contains '--help') -or ($referenceArgs -contains '-h')
$versionRequested = $ShowVersion -or $env:FLASH_VERSION -eq '1' -or ($referenceArgs -contains '--version')
if ($helpRequested -or $versionRequested) {
    Write-Output "stm32-flasher $VERSION"
    if ($helpRequested) {
        $ru = ($Lang -eq 'ru') -or (-not $Lang -and [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru')
        $command = 'flash.cmd'
        $example = 'flash.cmd -HexFile firmware.hex'
        $options = '-HexFile <file.hex>  -Sha256 <hash>'
        $description = if ($ru) { 'Прошивка и проверка STM32.' } else { 'Program and verify STM32 Flash.' }
        if ($Erase) {
            $command = 'erase.cmd'; $example = 'erase.cmd -Probe JLINK'
            $options = '-Engine <engine>  -Probe <STLINK|JLINK>  -Serial <serial>'
            $description = if ($ru) { 'Полное стирание Flash выбранного MCU.' } else { 'Erase all Flash of the selected MCU.' }
        } elseif ($Backup) {
            $command = 'backup.cmd'; $example = 'backup.cmd -Output backups/board.hex'
            $options = '-Output <file.hex>  -Address <address>  -Size <bytes>'
            $description = if ($ru) { 'Сохранение Flash в Intel HEX и SHA-256; по умолчанию в backups.' } else { 'Save Flash as Intel HEX and SHA-256; default folder: backups.' }
        } elseif ($Info) {
            $command = 'info.cmd'; $example = 'info.cmd -ProbeTarget'
            $options = '-ProbeTarget'
            $description = if ($ru) { 'Обзор ПК, инструментов, настроек, USB и HEX. -ProbeTarget подключается к MCU.' } else { 'Show PC, tools, settings, USB and HEX files. -ProbeTarget connects to the MCU.' }
        } elseif ($Clean -or $ResetConfig) {
            $command = 'forget.cmd'; $example = 'forget.cmd -DryRun'
            $options = '-DryRun'
            $description = if ($ru) { 'Удаление настроек, логов, отчётов и скачанных инструментов. HEX и backups сохраняются. flash.cmd -ResetConfig удаляет только настройки.' } else { 'Remove settings, logs, reports and downloaded tools. Preserve HEX and backups. flash.cmd -ResetConfig removes settings only.' }
        }
        Write-Output $description
        Write-Output "`n$command [options]"
        Write-Output "  $options"
        if (-not ($Clean -or $ResetConfig)) {
            Write-Output '  -Engine <CUBEPROGRAMMER|OPENOCD|JLINK|exe>  -Probe <STLINK|JLINK>'
            Write-Output '  -Serial <serial>  -Device <J-Link MCU>  -Target <OpenOCD cfg>'
            Write-Output '  -DryRun  -Silent'
        }
        Write-Output '  -Lang <ru|en>  --help / -Help / -h  --version / -Version'
        Write-Output "`n$example"
        if ($ru) { Write-Output 'Справочные ключи: только вывод, без выполнения операций и изменения файлов.' }
        else { Write-Output 'Help/version only print information; no operations or file changes.' }
    }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  Встроенные словари локализации (RU / EN)
# ══════════════════════════════════════════════════════════════════════════════

$LangRu = @{
    BackupName         = "Резервное копирование Flash"
    BackupSuccess      = "Резервная копия Flash сохранена"
    BackupError        = "Ошибка резервного копирования"
    BackupSize         = "Размер чтения в байтах (десятичный или 0x...)"
    BackupRange        = "Диапазон чтения"
    BackupFailed       = "Чтение не завершено или размер файла не соответствует запросу"
    BackupSizeConflict = "Размер Flash в регистре не совпадает с выбранной моделью MCU. Укажите размер явно через -Size."
    InfoEnvironment    = "Окружение ПК"
    InfoTools          = "Найденные инструменты и версии"
    InfoVersionUnknown = "версия не определена"
    InfoActiveTool     = "* Движок по текущим настройкам или автоматическому выбору"
    InfoToolPending    = "Движок ещё не выбран или его исполняемый файл недоступен"
    InfoSaved          = "Сохранённые настройки (не результаты обнаружения)"
    InfoUsb            = "USB-программаторы (без подключения к MCU)"
    InfoTarget         = "Информация о выбранном MCU"
    InfoDirectory      = "Рабочая папка"
    InfoFirmware       = "Прошивки в папке вызова (*.hex)"
    InfoFileSize       = "Размер файла"
    InfoBytes          = "байт"
    InfoChecksum       = "SHA-256 (файл, без проверки)"
    InfoNone           = "не найдено"
    EraseName          = "Полное стирание Flash"
    EraseRunning       = "Стирание Flash..."
    EraseSuccess       = "Flash микроконтроллера успешно стёрта"
    EraseError         = "Ошибка стирания Flash"
    EraseReport        = "Отчёт о стирании"
    ChooseDebugger     = "Выберите программатор"
    NoDebugger         = "Не удалось определить подключённые программаторы. Укажите тип и серийный номер явно."
    CleanupDone        = "Очистка завершена"
    CleanupPreview     = "Предпросмотр: файлы не удалены"
    ModeConflict       = "Выберите одну операцию и совместимые с ней параметры."
    BannerTitle         = "Утилита автоматической прошивки STM32"
    StepSearchHex       = "Поиск файлов прошивки..."
    ErrNoHex            = "Файлы .hex не найдены!"
    ListAvailable       = "Доступные прошивки:"
    PromptChoose        = "Выберите номер прошивки"
    PromptChooseEng     = "Выберите утилиту (рекомендуется CubeProgrammer)"
    Selected            = "Выбрано: "
    ErrBadChoice        = "Неверный выбор."
    InvalidHexFile      = "Указанный файл прошивки не найден или не является .hex: "
    InvalidEngine       = "Неверный движок. Возвращаемся к выбору..."
    InvalidTarget       = "Неверный параметр Target. Будет выбран автоматически."
    StepSelectEngine    = "Определение движка прошивки..."
    SearchCubeProg      = "Поиск STM32CubeProgrammer..."
    SearchStLinkInfo    = "Поиск st-info..."
    FoundEngines        = "Найдено несколько утилит прошивки:"
    EngineOpenOCD       = "OpenOCD (Встроенный/Автоматический)"
    EngineCubeProg      = "CubeProgrammer"
    EngineJLink         = "SEGGER J-Link"
    StepPrepareOpenOCD  = "Подготовка OpenOCD..."
    DownloadOpenOCD     = "Скачивание OpenOCD с GitHub (~5 MB)..."
    DownloadStLink      = "Скачивание stlink tools с GitHub (~1 MB)..."
    StepPrepareCubeProg = "Подготовка CubeProgrammer..."
    StepPrepareJLink    = "Подготовка SEGGER J-Link..."
    EngineOpenOCDCfg    = "Движок: OpenOCD (Конфиг: "
    EngineCubeProgName  = "Движок: STM32CubeProgrammer"
    EngineJLinkName     = "Движок: SEGGER J-Link"
    SearchJLink         = "Поиск SEGGER J-Link..."
    JLinkDevice         = "Устройство J-Link"
    PromptJLinkDevice   = "Введите имя устройства J-Link (например STM32G431CB)"
    InvalidJLinkDevice  = "Не указано устройство J-Link. Прошивка отменена."
    AutoDetectMcu       = "Автоопределение семейства микроконтроллера включено (через DAP)."
    Flashing            = "Прошивка..."
    TargetFoundIoc      = "Таргет найден в .ioc"
    TargetFoundProbe    = "Таргет определён через st-info"
    ProbeSkippedMulti   = "Найдено несколько ST-Link. Автоопределение таргета через st-info пока пропущено."
    ProbeUnavailable    = "st-info недоступен. Продолжаю стандартное определение таргета."
    ProbeFoundCount     = "st-info: найдено программаторов"
    ProbeChipId         = "st-info: chipid"
    ProbeNoChipId       = "st-info: chipid не распознан"
    ProbeNoTarget       = "st-info не смог сопоставить chipid с target OpenOCD"
    PromptChooseProbe   = "Выберите ST-Link"
    SelectedProbe       = "Выбран программатор"
    ProbeSerial         = "Серийный номер"
    ProbeFamily         = "Тип МК"
    ProbeType           = "Тип отладчика"
    InvalidProbe        = "Неверный тип отладчика. Использую STLINK."
    InvalidSerial       = "Указанный ST-Link serial не найден. Возвращаюсь к выбору..."
    RetryProbeSerial    = "OpenOCD не принял serial в текстовом виде, повторяю с байтовым форматом"
    RetryWithoutSerial  = "Сохранённый serial не подошёл, повторяю без serial"
    IntegrityCheck      = "Контроль целостности"
    IntegrityNotChecked = "Не выполнялся"
    IntegrityPassed     = "SHA-256 подтверждён"
    IntegrityFailed     = "SHA-256 не совпадает"
    IntegritySource     = "Источник SHA-256"
    IntegrityExpected   = "Ожидаемый SHA-256"
    IntegrityActual     = "Вычисленный SHA-256"
    IntegritySourceCli  = "Параметр -Sha256"
    IntegritySourceFile = "Файл .sha256"
    IntegrityFound      = "Найдена контрольная сумма"
    IntegrityInvalid    = "Не удалось прочитать SHA-256 из файла"
    IntegrityAbort      = "SHA-256 не совпадает. Прошивка отменена."
    HistoryTitle        = "История прошивок"
    HistorySessionTime  = "Время"
    HistoryResult       = "Результат"
    HistoryFirmware     = "Прошивка"
    HistoryEngine       = "Движок"
    HistoryDuration     = "Длительность"
    HistoryReport       = "Отчёт"
    HistoryLog          = "Лог"
    HistoryOpen         = "Открыть"
    HistoryIndexNote    = "Показаны последние сессии"
    NoTargetDef         = "Не удалось определить семейство. Введите название cfg (например target/stm32f4x.cfg):"
    OkSuccess           = "УСПЕШНО! Прошивка загружена и проверена."
    ErrFailed           = "Что-то пошло не так. Exit code: "
    OpeningReport       = "Открываю отчёт..."

    # DRY RUN
    DryRunSimulating    = "DRY RUN: Симуляция процесса прошивки..."
    DryRunLog           = "DRY RUN: Имитация успешной прошивки"
    HtmlTitle           = "Отчёт о прошивке"
    StatusStages        = "Статус этапов"
    Build               = "Сборка"
    Scheme              = "Схема прошивки"
    Host                = "Хост"
    ScriptVersion       = "Версия скрипта"
    Operator            = "Оператор"
    UserAccount         = "Учётная запись"
    Machine             = "Машина"
    NetworkHost         = "Сетевое имя"
    OS                  = "Операционная система"
    PowerShell          = "PowerShell"
    FlashEngine         = "Движок прошивки"
    Programmer          = "Программатор"
    StLink              = "Отладчик / программатор"
    TargetVoltage       = "Напряжение питания МК"
    Mcu                 = "Микроконтроллер"
    Family              = "Семейство"
    Core                = "Ядро / Процессор"
    DeviceId            = "Device ID"
    Flash               = "Flash"
    StLinkDetected      = "Программатор обнаружен"
    Yes                 = "Да"
    No                  = "Нет — проверьте USB и питание"
    FlashWrite          = "Запись во Flash"
    WriteCompleted      = "Завершена"
    WriteError          = "Ошибка записи"
    Verification        = "Верификация"
    VerPassed           = "Пройдена"
    VerFailed           = "Провалена"
    ExitCode            = "Код выхода утилиты"
    OperationDuration   = "Длительность операции"
    ConsoleDuration     = "Общее время"
    ExitSuccess         = "0 (успех)"
    ExitError           = "(ошибка)"
    SuccessMsg          = "Прошивка завершена успешно"
    ErrorMsg            = "Ошибка прошивки — см. детали и лог ниже"
    Changelog           = "История изменений (CHANGELOG)"
    ToolOutput          = "Вывод утилиты"
    ToolNotDetected     = "не удалось определить"
    StLinkNotFound      = "не обнаружен"
    DownloadFailed      = "Все методы загрузки не удались.`nСкачайте OpenOCD вручную: "
    DownloadWhere       = "`nРаспакуйте в: "
    Source              = "Источник"
    ReportTimeLocal     = "Локальное время"
    ReportTimeUtc       = "UTC"
}

$LangEn = @{
    BackupName         = "Flash backup"
    BackupSuccess      = "Flash backup saved"
    BackupError        = "Flash backup failed"
    BackupSize         = "Read size in bytes (decimal or 0x...)"
    BackupRange        = "Read range"
    BackupFailed       = "Read failed or file size does not match the requested range"
    BackupSizeConflict = "Flash size register differs from the selected MCU model. Specify the size explicitly using -Size."
    InfoEnvironment    = "PC environment"
    InfoTools          = "Discovered tools and versions"
    InfoVersionUnknown = "version unavailable"
    InfoActiveTool     = "* Engine selected by current settings or automatic selection"
    InfoToolPending    = "Engine selection is pending or its executable is unavailable"
    InfoSaved          = "Saved settings (not detected hardware)"
    InfoUsb            = "USB probes (without connecting to MCU)"
    InfoTarget         = "Selected MCU information"
    InfoDirectory      = "Working directory"
    InfoFirmware       = "Firmware in the working directory (*.hex)"
    InfoFileSize       = "File size"
    InfoBytes          = "bytes"
    InfoChecksum       = "SHA-256 (file, not verified)"
    InfoNone           = "not found"
    EraseName          = "Full Flash erase"
    EraseRunning       = "Erasing Flash..."
    EraseSuccess       = "MCU Flash erased successfully"
    EraseError         = "Flash erase failed"
    EraseReport        = "Erase Report"
    ChooseDebugger     = "Select programmer"
    NoDebugger         = "Cannot enumerate connected probes. Specify probe type and serial explicitly."
    CleanupDone        = "Cleanup completed"
    CleanupPreview     = "Preview: no files deleted"
    ModeConflict       = "Select one operation and compatible parameters."
    BannerTitle         = "STM32 Automatic Flashing Utility"
    StepSearchHex       = "Searching for firmware files..."
    ErrNoHex            = "No .hex files found!"
    ListAvailable       = "Available firmwares:"
    PromptChoose        = "Select firmware number"
    PromptChooseEng     = "Select flashing utility (CubeProgrammer recommended)"
    Selected            = "Selected: "
    ErrBadChoice        = "Invalid choice."
    InvalidHexFile      = "Specified firmware file was not found or is not .hex: "
    InvalidEngine       = "Invalid engine specified. Falling back to interactive selection..."
    InvalidTarget       = "Invalid Target parameter. It will be selected automatically."
    StepSelectEngine    = "Determining flashing engine..."
    SearchCubeProg      = "Searching for STM32CubeProgrammer..."
    SearchStLinkInfo    = "Searching for st-info..."
    FoundEngines        = "Multiple flashing utilities found:"
    EngineOpenOCD       = "OpenOCD (Built-in/Automatic)"
    EngineCubeProg      = "CubeProgrammer"
    EngineJLink         = "SEGGER J-Link"
    StepPrepareOpenOCD  = "Preparing OpenOCD..."
    DownloadOpenOCD     = "Downloading OpenOCD from GitHub (~5 MB)..."
    DownloadStLink      = "Downloading stlink tools from GitHub (~1 MB)..."
    StepPrepareCubeProg = "Preparing CubeProgrammer..."
    StepPrepareJLink    = "Preparing SEGGER J-Link..."
    EngineOpenOCDCfg    = "Engine: OpenOCD (Config: "
    EngineCubeProgName  = "Engine: STM32CubeProgrammer"
    EngineJLinkName     = "Engine: SEGGER J-Link"
    SearchJLink         = "Searching for SEGGER J-Link..."
    JLinkDevice         = "J-Link Device"
    PromptJLinkDevice   = "Enter J-Link device name (for example STM32G431CB)"
    InvalidJLinkDevice  = "J-Link device was not specified. Flashing aborted."
    AutoDetectMcu       = "Microcontroller auto-detection enabled (via DAP)."
    Flashing            = "Flashing..."
    TargetFoundIoc      = "Target found in .ioc"
    TargetFoundProbe    = "Target resolved via st-info"
    ProbeSkippedMulti   = "Multiple ST-Link devices found. Target auto-detection via st-info is skipped for now."
    ProbeUnavailable    = "st-info is unavailable. Falling back to standard target detection."
    ProbeFoundCount     = "st-info: programmers found"
    ProbeChipId         = "st-info: chipid"
    ProbeNoChipId       = "st-info: chipid not recognized"
    ProbeNoTarget       = "st-info could not map chipid to an OpenOCD target"
    PromptChooseProbe   = "Select ST-Link"
    SelectedProbe       = "Selected programmer"
    ProbeSerial         = "Serial"
    ProbeFamily         = "MCU"
    ProbeType           = "Probe type"
    InvalidProbe        = "Invalid probe type. Falling back to STLINK."
    InvalidSerial       = "Specified ST-Link serial was not found. Falling back to selection..."
    RetryProbeSerial    = "OpenOCD did not accept the plain serial, retrying with byte format"
    RetryWithoutSerial  = "Saved serial did not work, retrying without serial"
    IntegrityCheck      = "Integrity Check"
    IntegrityNotChecked = "Not performed"
    IntegrityPassed     = "SHA-256 verified"
    IntegrityFailed     = "SHA-256 mismatch"
    IntegritySource     = "SHA-256 Source"
    IntegrityExpected   = "Expected SHA-256"
    IntegrityActual     = "Computed SHA-256"
    IntegritySourceCli  = "Parameter -Sha256"
    IntegritySourceFile = ".sha256 file"
    IntegrityFound      = "Checksum found"
    IntegrityInvalid    = "Could not read SHA-256 from file"
    IntegrityAbort      = "SHA-256 mismatch. Flashing aborted."
    HistoryTitle        = "Flash History"
    HistorySessionTime  = "Time"
    HistoryResult       = "Result"
    HistoryFirmware     = "Firmware"
    HistoryEngine       = "Engine"
    HistoryDuration     = "Duration"
    HistoryReport       = "Report"
    HistoryLog          = "Log"
    HistoryOpen         = "Open"
    HistoryIndexNote    = "Latest sessions shown"
    NoTargetDef         = "Could not determine family. Enter config name (e.g., target/stm32f4x.cfg):"
    OkSuccess           = "SUCCESS! Firmware loaded and verified."
    ErrFailed           = "Something went wrong. Exit code: "
    OpeningReport       = "Opening report..."

    # DRY RUN
    DryRunSimulating    = "DRY RUN: Simulating flash process..."
    DryRunLog           = "DRY RUN: Simulated successful flash"
    HtmlTitle           = "Flash Report"
    StatusStages        = "Stage Status"
    Build               = "Build"
    Scheme              = "Flash Scheme"
    Host                = "Host"
    ScriptVersion       = "Script Version"
    Operator            = "Operator"
    UserAccount         = "User Account"
    Machine             = "Machine"
    NetworkHost         = "Network Host"
    OS                  = "Operating System"
    PowerShell          = "PowerShell"
    FlashEngine         = "Flash Engine"
    Programmer          = "Programmer"
    StLink              = "Probe / Programmer"
    TargetVoltage       = "Target Voltage"
    Mcu                 = "Microcontroller"
    Family              = "Family"
    Core                = "Core / Processor"
    DeviceId            = "Device ID"
    Flash               = "Flash"
    StLinkDetected      = "Programmer Detected"
    Yes                 = "Yes"
    No                  = "No — check USB and power"
    FlashWrite          = "Flash Write"
    WriteCompleted      = "Completed"
    WriteError          = "Write Error"
    Verification        = "Verification"
    VerPassed           = "Passed"
    VerFailed           = "Failed"
    ExitCode            = "Utility Exit Code"
    OperationDuration   = "Operation Duration"
    ConsoleDuration     = "Total Time"
    ExitSuccess         = "0 (success)"
    ExitError           = "(error)"
    SuccessMsg          = "Flashing completed successfully"
    ErrorMsg            = "Flashing error — see details and log below"
    Changelog           = "Change History (CHANGELOG)"
    ToolOutput          = "Utility Output"
    ToolNotDetected     = "could not be determined"
    StLinkNotFound      = "not detected"
    DownloadFailed      = "All download methods failed.`nDownload OpenOCD manually: "
    DownloadWhere       = "`nExtract to: "
    Source              = "Source"
    ReportTimeLocal     = "Local time"
    ReportTimeUtc       = "UTC"
}

# Выбор активного словаря и функция перевода
if ($Lang -eq "en") {
    $ActiveLang = $LangEn
} elseif ($Lang -eq "ru") {
    $ActiveLang = $LangRu
} else {
    # Автовыбор по системной локали
    if ($PSUICulture -match "^ru") {
        $ActiveLang = $LangRu
    } else {
        $ActiveLang = $LangEn
    }
}

function T($key) {
    $val = $ActiveLang[$key]
    if ($null -eq $val) { return $key }
    return $val
}

function Resolve-HexPath($value) {
    if (-not $value) { return $null }
    $candidate = $value.Trim('"')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Get-Item -LiteralPath $candidate).FullName }
    $baseDir = if ($env:SCRIPT_PATH) { Split-Path -Parent $env:SCRIPT_PATH }
    elseif ($PSScriptRoot -and $PSScriptRoot -ne '\' -and $PSScriptRoot -ne '/') { $PSScriptRoot }
    else { (Get-Location).Path }
    if (-not $baseDir) { return $null }
    $candidate = Join-Path $baseDir $candidate
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Get-Item -LiteralPath $candidate).FullName }
    return $null
}

# Normalize CLI arguments: positional file/lang support, named params optional
if (-not $Lang -and $Input) {
    if ($Input -in @('ru','en')) {
        $Lang = $Input
    } else {
        $HexFile = if ($HexFile) { $HexFile } else { $Input }
    }
}

if ($Lang -eq 'en') {
    $ActiveLang = $LangEn
} elseif ($Lang -eq 'ru') {
    $ActiveLang = $LangRu
} else {
    if ($PSUICulture -match '^ru') { $ActiveLang = $LangRu } else { $ActiveLang = $LangEn }
}

$NoFirmware = $Erase -or $Backup -or $Info
$FreshProbeSelection = $Erase -or $Backup -or ($Info -and $ProbeTarget)
if ((@($Erase, $Backup, $Info, $ResetConfig, $Clean | Where-Object { $_ }).Count -gt 1) -or
    ($ProbeTarget -and -not $Info) -or (($Output -or $Size -or $Address) -and -not $Backup) -or
    ($NoFirmware -and ($HexFile -or $Sha256 -or ($Input -and $Input -notin @('ru','en')))) -or
    (($ResetConfig -or $Clean) -and ($Erase -or $HexFile -or $Sha256 -or $Engine -or $Device -or $Target -or $Probe -or $Serial)) -or
    ($ResetConfig -and $Clean)) {
    Write-Host (T 'ModeConflict')
    exit 1
}

if ($Erase) {
    $ActiveLang['Flashing'] = T 'EraseRunning'
    $ActiveLang['OkSuccess'] = T 'EraseSuccess'
    $ActiveLang['SuccessMsg'] = T 'EraseSuccess'
    $ActiveLang['ErrorMsg'] = T 'EraseError'
    $ActiveLang['HtmlTitle'] = T 'EraseReport'
}
if ($Backup) {
    $ActiveLang['Flashing'] = T 'BackupName'
    $ActiveLang['OkSuccess'] = T 'BackupSuccess'
    $ActiveLang['SuccessMsg'] = T 'BackupSuccess'
    $ActiveLang['ErrorMsg'] = T 'BackupError'
    $ActiveLang['HtmlTitle'] = T 'BackupName'
}

if ($HexFile) {
    $ResolvedHex = Resolve-HexPath $HexFile
    if ($ResolvedHex) {
        $HexFile = $ResolvedHex
    } else {
        Write-Host "   [!] $(T 'InvalidHexFile')$HexFile" -ForegroundColor Yellow
        $HexFile = ""
    }
}

$SelectedEngine = ""
if ($Engine) {
    if (($Engine -ieq 'OPENOCD') -or ($Engine -ieq 'JLINK') -or ($Engine -ieq 'CUBEPROGRAMMER') -or ($Engine -ieq 'CUBE') -or (Test-Path -LiteralPath $Engine -PathType Leaf)) {
        $SelectedEngine = $Engine
    } else {
        if ($NoFirmware) { throw (T 'InvalidEngine') }
        Write-Host "   [!] $(T 'InvalidEngine')" -ForegroundColor Yellow
        $Engine = ""
    }
}

if ($Input -and -not $HexFile -and $Input -notin @('ru','en')) {
    $ResolvedInput = Resolve-HexPath $Input
    if ($ResolvedInput) {
        $HexFile = $ResolvedInput
    } else {
        Write-Host "   [!] $(T 'InvalidHexFile')$Input" -ForegroundColor Yellow
    }
}

if (-not $Silent) {
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "  $(T 'BannerTitle') v$VERSION" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
}

# ══════════════════════════════════════════════════════════════════════════════
#  Вспомогательные функции — вывод
# ══════════════════════════════════════════════════════════════════════════════

function Write-Step($n, $text) { if (-not $Silent) { Write-Host "`n$n. $text" -ForegroundColor Cyan } }
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

function Normalize-ToolLog($text) {
    if (-not $text) { return "" }
    $replacementChar = [regex]::Escape([string][char]0xFFFD)
    $lines = $text -split "`r?`n"
    $normalized = foreach ($line in $lines) {
        $clean = $line
        if ($clean -match $replacementChar) {
            $clean = $clean -replace "$replacementChar+", "="
            $clean = $clean -replace '=+\s*(\d+%)', '= $1'
        }
        $clean.TrimEnd()
    }
    return ($normalized -join "`n").TrimEnd()
}

function Status-Row($label, $ok, $okText, $failText) {
    if ($ok) { return "<tr><th>$label</th><td><span class='ok'>&#10003; $okText</span></td></tr>" }
    else     { return "<tr><th>$label</th><td><span class='err'>&#10007; $failText</span></td></tr>" }
}

function Get-LogMatchValue($text, $pattern) {
    if (-not $text -or -not $pattern) { return "" }
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success -or $match.Groups.Count -lt 2) { return "" }
    return $match.Groups[1].Value.Trim()
}

function Invoke-EngineLogParser($text, $patternSet) {
    $result = [ordered]@{
        IsStlinkFound = $false
        IsProgrammed  = $false
        IsVerified    = $false
        ToolInfo      = ""
        StlinkInfo    = ""
        TargetVoltage = ""
        McuCore       = ""
        McuDevId      = ""
        McuDevIdHex   = ""
        McuFlash      = ""
        McuFamily     = ""
    }
    if (-not $patternSet) { return [PSCustomObject]$result }

    foreach ($flagName in @("IsStlinkFound", "IsProgrammed", "IsVerified")) {
        $pattern = $patternSet.Flags[$flagName]
        if ($pattern) { $result[$flagName] = [regex]::IsMatch($text, $pattern) }
    }

    foreach ($fieldName in $patternSet.Fields.Keys) {
        $spec = $patternSet.Fields[$fieldName]
        $value = Get-LogMatchValue $text $spec.Pattern
        if ($value -and $spec.Prefix) { $value = "$($spec.Prefix)$value" }
        if ($value -and $spec.Suffix) { $value = "$value$($spec.Suffix)" }
        if ($value) { $result[$fieldName] = $value }
    }

    if ($result.McuDevIdHex -and -not $result.McuDevId) {
        $result.McuDevId = $result.McuDevIdHex
    }
    if (-not $result.McuFamily -and $result.McuDevIdHex) {
        $result.McuFamily = Get-Stm32Family $result.McuDevIdHex
    }

    return [PSCustomObject]$result
}

function Write-HistoryIndex($historyDir, $entries) {
    if (-not $historyDir) { return }
    $sorted = @($entries | Sort-Object TimestampUtc -Descending | Select-Object -First 20)
    $rows = foreach ($entry in $sorted) {
        $timeLocal = if ($entry.TimestampLocal) { Escape-Html $entry.TimestampLocal } else { "<em class='na'>—</em>" }
        $resultClass = if ($entry.Success) { "ok" } else { "err" }
        $resultText = if ($entry.ResultText) { Escape-Html $entry.ResultText } else { "<em class='na'>—</em>" }
        $firmware = if ($entry.HexName) { Escape-Html $entry.HexName } else { "<em class='na'>—</em>" }
        $engine = if ($entry.EngineName) { Escape-Html $entry.EngineName } else { "<em class='na'>—</em>" }
        $duration = if ($entry.OperationDuration) { "<code>$(Escape-Html $entry.OperationDuration)</code>" } else { "<em class='na'>—</em>" }
        $reportLink = if ($entry.ReportFile) { "<a href='$(Escape-Html $entry.ReportFile)'>$(T 'HistoryOpen')</a>" } else { "<em class='na'>—</em>" }
        $logLink = if ($entry.LogFile) { "<a href='$(Escape-Html $entry.LogFile)'>$(T 'HistoryOpen')</a>" } else { "<em class='na'>—</em>" }
        "<tr><td>$timeLocal</td><td><span class='$resultClass'>$resultText</span></td><td>$firmware</td><td>$engine</td><td>$duration</td><td>$reportLink</td><td>$logLink</td></tr>"
    }
    $rowsHtml = if ($rows) { $rows -join "`n" } else { "<tr><td colspan='7'><em class='na'>—</em></td></tr>" }
    $indexHtml = @"
<!DOCTYPE html>
<html lang="$( if ($ActiveLang -eq $LangRu) { 'ru' } else { 'en' } )">
<head>
  <meta charset="UTF-8">
  <title>$(T 'HistoryTitle')</title>
  <style>
    body { font-family: 'Segoe UI', system-ui, Arial, sans-serif; background: #eef0f4; color: #212529; padding: 28px 36px; }
    .card { background: #fff; border-radius: 10px; box-shadow: 0 1px 4px rgba(0,0,0,.09); padding: 18px 22px; }
    h1 { font-size: 1.3rem; margin-bottom: 6px; }
    .sub { color: #868e96; font-size: .82rem; margin-bottom: 18px; }
    table { width: 100%; border-collapse: collapse; font-size: .86rem; }
    th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #f0f0f0; vertical-align: top; }
    th { background: #f8f9fa; font-weight: 600; color: #495057; white-space: nowrap; }
    tr:nth-child(even) td { background: #fcfcfd; }
    .ok { color: #198754; font-weight: 600; }
    .err { color: #dc3545; font-weight: 600; }
    .na { color: #adb5bd; font-style: italic; }
    code { background: #f1f3f5; padding: 1px 5px; border-radius: 3px; font-size: .82rem; font-family: 'Consolas', monospace; }
    a { color: #0d6efd; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="card">
    <h1>$(T 'HistoryTitle')</h1>
    <p class="sub">$(T 'HistoryIndexNote'): $($sorted.Count)</p>
    <table>
      <tr>
        <th>$(T 'HistorySessionTime')</th>
        <th>$(T 'HistoryResult')</th>
        <th>$(T 'HistoryFirmware')</th>
        <th>$(T 'HistoryEngine')</th>
        <th>$(T 'HistoryDuration')</th>
        <th>$(T 'HistoryReport')</th>
        <th>$(T 'HistoryLog')</th>
      </tr>
      $rowsHtml
    </table>
  </div>
</body>
</html>
"@
    Set-Content -LiteralPath (Join-Path $historyDir "index.html") -Value $indexHtml -Encoding UTF8
}

function Save-HistoryArtifacts($historyDir, $logFile, $htmlReport, $entry) {
    if (-not $historyDir -or -not $entry) { return }
    New-Item -ItemType Directory -Force -Path $historyDir | Out-Null
    $stamp = $entry.TimestampTag
    $reportName = "report_$stamp.html"
    $logName = "flash_$stamp.log"
    $metaName = "session_$stamp.json"
    Copy-Item -LiteralPath $htmlReport -Destination (Join-Path $historyDir $reportName) -Force
    Copy-Item -LiteralPath $logFile -Destination (Join-Path $historyDir $logName) -Force
    $entry["ReportFile"] = $reportName
    $entry["LogFile"] = $logName
    $entry | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $historyDir $metaName) -Encoding UTF8

    $allEntries = @()
    foreach ($metaFile in (Get-ChildItem -LiteralPath $historyDir -Filter "session_*.json" -ErrorAction SilentlyContinue)) {
        try {
            $allEntries += (Get-Content -LiteralPath $metaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {}
    }
    Write-HistoryIndex $historyDir $allEntries
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

function Find-Sha256File($targetPath) {
    if (-not $targetPath) { return $null }
    $candidates = @(
        "$targetPath.sha256",
        ([System.IO.Path]::ChangeExtension($targetPath, ".sha256"))
    ) | Select-Object -Unique
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }
    return $null
}

function Parse-Sha256Value($text) {
    if (-not $text) { return $null }
    foreach ($line in ($text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -match '([A-Fa-f0-9]{64})') {
            return $Matches[1].ToUpperInvariant()
        }
    }
    return $null
}

function Get-Stm32Family($deviceIdHex) {
    if (-not $deviceIdHex) { return $null }
    $raw = $deviceIdHex -replace '^0x',''
    try { $id = [int](([Convert]::ToInt64($raw, 16)) -band 0xFFF) } catch { return $null }

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
    throw "$(T 'DownloadFailed')$url$(T 'DownloadWhere')$ToolDir"
}

function Find-StInfoExe() {
    $candidates = @()

    try {
        $cmd = Get-Command "st-info.exe" -ErrorAction Stop
        if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
    } catch {}

    if ($env:USERPROFILE) {
        $candidates += (Join-Path $env:USERPROFILE "scoop\apps\stlink\current\bin\st-info.exe")
    }

    $candidates += @(
        "C:\Program Files (x86)\stlink\bin\st-info.exe",
        "C:\Program Files\stlink\bin\st-info.exe"
    )

    $stlinkToolRoot = Join-Path $ToolDir "stlink"
    if (Test-Path -LiteralPath $stlinkToolRoot) {
        $found = Get-ChildItem -Path $stlinkToolRoot -Recurse -Filter "st-info.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $candidates += $found.FullName }
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Ensure-StInfoExe() {
    $stInfoExe = Find-StInfoExe
    if ($stInfoExe) { return $stInfoExe }

    Write-Warn (T "DownloadStLink")
    $stlinkToolRoot = Join-Path $ToolDir "stlink"
    $stlinkZip = Join-Path $ToolDir "stlink.zip"

    New-Item -ItemType Directory -Force -Path $stlinkToolRoot | Out-Null
    Invoke-Download $StLinkUrl $stlinkZip
    Expand-Archive -Path $stlinkZip -DestinationPath $stlinkToolRoot -Force
    Remove-Item -LiteralPath $stlinkZip -ErrorAction SilentlyContinue

    $stInfoExe = Find-StInfoExe
    if ($stInfoExe) { return $stInfoExe }

    throw "st-info.exe was not found after extracting stlink tools."
}

function Get-OpenOcdTargetFromDeviceId($deviceIdHex) {
    $family = Get-Stm32Family $deviceIdHex
    if (-not $family) { return $null }

    if ($family -like 'STM32WB*') { return 'target/stm32wbx.cfg' }
    if ($family -like 'STM32WL*') { return 'target/stm32wlx.cfg' }
    if ($family -match '^STM32([FHGUL])(\d)') { return "target/stm32$($Matches[1].ToLower())$($Matches[2])x.cfg" }

    return $null
}

function Get-StInfoProbeInfo($stInfoExe) {
    # Capture stderr as text: PS 5.1 otherwise treats libusb warnings as terminating errors.
    $probeResult = Invoke-ReadTool $stInfoExe @('--probe')
    $probeText = $probeResult.Log.Trim()
    $probeCount = 0
    if ($probeText -match 'Found\s+(\d+)\s+stlink programmers') {
        $probeCount = [int]$Matches[1]
    }

    $entries = @()
    if ($probeCount -gt 1) {
        $blocks = [regex]::Split($probeText, '(?m)^\s*\d+\.\s*$') | Where-Object { $_.Trim() }
        foreach ($block in $blocks) {
            $serial = $null
            $chipIdHex = $null
            $version = $null
            if ($block -match 'version:\s*([^\r\n]+)') { $version = $Matches[1].Trim() }
            if ($block -match 'serial:\s*([0-9A-Fa-f]+)') { $serial = $Matches[1] }
            if ($block -match 'chipid:\s*(0x[\da-fA-F]+)') { $chipIdHex = $Matches[1] }
            if (-not $serial -and -not $chipIdHex -and -not $version) { continue }
            $family = if ($chipIdHex) { Get-Stm32Family $chipIdHex } else { $null }
            $targetCfg = if ($chipIdHex) { Get-OpenOcdTargetFromDeviceId $chipIdHex } else { $null }
            $entries += [PSCustomObject]@{
                Version = $version
                Serial = $serial
                ChipIdHex = $chipIdHex
                Family = $family
                TargetCfg = $targetCfg
            }
        }
    } elseif ($probeCount -eq 1) {
        $serial = $null
        $chipIdHex = $null
        $version = $null
        if ($probeText -match 'version:\s*([^\r\n]+)') { $version = $Matches[1].Trim() }
        if ($probeText -match 'serial:\s*([0-9A-Fa-f]+)') { $serial = $Matches[1] }
        if ($probeText -match 'chipid:\s*(0x[\da-fA-F]+)') { $chipIdHex = $Matches[1] }
        $family = if ($chipIdHex) { Get-Stm32Family $chipIdHex } else { $null }
        $targetCfg = if ($chipIdHex) { Get-OpenOcdTargetFromDeviceId $chipIdHex } else { $null }
        $entries += [PSCustomObject]@{
            Version = $version
            Serial = $serial
            ChipIdHex = $chipIdHex
            Family = $family
            TargetCfg = $targetCfg
        }
    }

    return [PSCustomObject]@{
        Count = $probeCount
        Entries = $entries
        Output = $probeText
    }
}

function Convert-ToHlaSerial($serialHex) {
    if (-not $serialHex) { return $null }
    $bytes = @()
    for ($i = 0; $i -lt $serialHex.Length; $i += 2) {
        if ($i + 1 -lt $serialHex.Length) {
            $bytes += "\x$($serialHex.Substring($i, 2).ToLower())"
        }
    }
    return ($bytes -join '')
}

function Get-OpenOcdSerialCommand($serialHex, $mode = "plain") {
    if (-not $serialHex) { return $null }
    switch ($mode) {
        "bytes" { return "adapter serial `"$((Convert-ToHlaSerial $serialHex))`"" }
        default { return "adapter serial `"$serialHex`"" }
    }
}

function Test-IsJLinkEngine($engine) {
    if (-not $engine) { return $false }
    if ($engine -ieq "JLINK") { return $true }
    $leaf = Split-Path -Leaf $engine -ErrorAction SilentlyContinue
    return ($leaf -ieq "JLink.exe")
}

function Find-JLinkExe() {
    $candidates = @()

    try {
        $cmd = Get-Command "JLink.exe" -ErrorAction Stop
        if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
    } catch {}

    $candidates += @(
        "C:\Program Files\SEGGER\JLink\JLink.exe",
        "C:\Program Files (x86)\SEGGER\JLink\JLink.exe"
    )

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    return $null
}

function Find-CubeProgrammerCli() {
    $searchPaths = @(
        "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\ST\STM32CubeCLT*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\ST\STM32CubeIDE*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "$env:LOCALAPPDATA\Programs\STM32CubeCLT*\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    )
    $foundCli = @()
    foreach ($p in $searchPaths) {
        $found = Get-Item -Path $p -ErrorAction SilentlyContinue
        if ($found) { $foundCli += $found.FullName }
    }
    return @($foundCli | Select-Object -Unique)
}

function Get-EngineDisplayName($engine) {
    if ($engine -eq "OPENOCD") { return "OpenOCD" }
    if (Test-IsJLinkEngine $engine) { return "SEGGER J-Link" }
    if ($engine) { return "STM32CubeProgrammer" }
    return ""
}

function ConvertFrom-JLinkProbeList($output) {
    foreach ($match in [regex]::Matches($output, 'J-Link\[\d+\]:[^\r\n]*Serial number:\s*(\d+),\s*ProductName:\s*([^\r\n]+)')) {
        [PSCustomObject]@{ Serial = $match.Groups[1].Value; Family = $match.Groups[2].Value.Trim(); Type = 'JLINK' }
    }
}

function Get-JLinkProbes {
    $exe = Find-JLinkExe
    if (-not $exe) { return }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = '-nogui 1'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $start
    try {
        [void]$proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.WriteLine('ShowEmuList USB')
        $proc.StandardInput.WriteLine('q')
        $proc.StandardInput.Close()
        if (-not $proc.WaitForExit(10000)) { $proc.Kill(); throw (T 'NoDebugger') }
        $output = $outTask.GetAwaiter().GetResult()
        [void]$errTask.GetAwaiter().GetResult()
        if ($output -match 'SEGGER J-Link Commander\s+(V\S+)') { $script:DetectedJLinkVersion = $Matches[1] }
        ConvertFrom-JLinkProbeList $output
    } finally { $proc.Dispose() }
}

function Save-LaunchSetting($path, $value) {
    if (-not $DryRun -and -not $Info) {
        Set-Content -LiteralPath $path -Value $value -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

function Select-ConnectedProbe($entries) {
    if ($entries.Count -eq 1) { return $entries[0] }
    for ($i = 0; $i -lt $entries.Count; $i++) {
        Write-Host "     [$($i + 1)] $($entries[$i].Type) | $($entries[$i].Serial) | $($entries[$i].Family)"
    }
    $answer = Read-Host (T 'ChooseDebugger')
    $number = 0
    if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $entries.Count) {
        throw (T 'ErrBadChoice')
    }
    return $entries[$number - 1]
}

function Test-EraseLog($parser, $log) {
    $pattern = switch ($parser) {
        'JLINK' { '(?m)^Erasing done\.\s*$' }
        'OPENOCD' { '(?m)^FLASH_ERASE_COMPLETE\s*$' }
        default { '(?im)^\s*Mass erase successfully achieved\.?\s*$' }
    }
    return $log -match $pattern
}

function Get-UsbStLinkProbes {
    try { $devices = Get-CimInstance Win32_PnPEntity -ErrorAction Stop } catch {
        $listing = (& pnputil.exe /enum-devices /connected /bus USB | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'USB enumeration failed.' }
        $devices = foreach ($match in [regex]::Matches($listing, '(?im)USB\\VID_0483&PID_37[0-9A-F]{2}\\[^\s\\]+')) {
            [PSCustomObject]@{ PNPDeviceID = $match.Value; Name = 'ST-Link (USB)' }
        }
    }
    $seen = @{}
    foreach ($item in $devices) {
        if ($item.PNPDeviceID -match '^USB\\VID_0483&PID_(3744|3748|374A|374B|374D|374E|374F|3752|3753|3754)\\([^\\]+)$') {
            $usbSerial = $Matches[2]
            if (-not $seen[$usbSerial]) {
                $seen[$usbSerial] = $true
                [PSCustomObject]@{ Type = 'STLINK'; Serial = $usbSerial; Family = $item.Name }
            }
        }
    }
}

function Get-ToolVersion($path) {
    if ((Test-IsJLinkEngine $path) -and $script:DetectedJLinkVersion) { return $script:DetectedJLinkVersion }
    $leaf = [IO.Path]::GetFileName($path)
    if ($leaf -in @('STM32_Programmer_CLI.exe', 'st-info.exe', 'openocd.exe')) {
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $path
        $start.Arguments = '--version'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $proc = New-Object Diagnostics.Process
        $proc.StartInfo = $start
        try {
            [void]$proc.Start()
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            if (-not $proc.WaitForExit(10000)) {
                $proc.Kill()
            } elseif ($proc.ExitCode -eq 0 -and [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 1000)) {
                $banner = $stdoutTask.Result + "`n" + $stderrTask.Result
                switch ($leaf) {
                    'STM32_Programmer_CLI.exe' {
                        if ($banner -match '(?im)^\s*STM32CubeProgrammer(?:\s+version:)?\s+v?([0-9]+\.[0-9]+[^\s]*)') { return $Matches[1] }
                    }
                    'st-info.exe' {
                        if ($banner -match '(?im)^\s*v?([0-9]+\.[0-9]+[^\s]*)\s*$') { return $Matches[1] }
                    }
                    'openocd.exe' {
                        if ($banner -match '(?im)^\s*(?:xPack\s+)?Open On-Chip Debugger\s+([^\r\n]+)') { return $Matches[1].Trim() }
                    }
                }
            }
        } catch {
            # A missing/broken tool should not prevent the rest of the inventory.
        } finally { $proc.Dispose() }
    }
    $fileVersion = (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    if ($fileVersion) { return $fileVersion }
    return (T 'InfoVersionUnknown')
}

function Find-OpenOcdInstallation($managedExe) {
    $candidates = @($managedExe)
    $command = Get-Command openocd.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    if ($env:SCOOP) { $candidates += Join-Path $env:SCOOP 'apps/openocd/current/bin/openocd.exe' }
    if ($env:USERPROFILE) { $candidates += Join-Path $env:USERPROFILE 'scoop/apps/openocd/current/bin/openocd.exe' }
    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $root = Split-Path -Parent (Split-Path -Parent $candidate)
        foreach ($relative in @('openocd/scripts', 'share/openocd/scripts', 'scripts')) {
            $scripts = Join-Path $root $relative
            if (Test-Path -LiteralPath (Join-Path $scripts 'interface/stlink.cfg')) {
                return [PSCustomObject]@{ Exe = $candidate; Scripts = $scripts }
            }
        }
    }
    return $null
}

function Get-InfoEnginePath($cubePaths, $jlinkPath) {
    $choice = $SelectedEngine
    $savedPath = Join-Path $CurrentDir '.flash_engine'
    if (-not $choice -and (Test-Path -LiteralPath $savedPath)) {
        $saved = (Get-Content -LiteralPath $savedPath -TotalCount 1 -Encoding UTF8).Trim()
        if ($saved -in @('OPENOCD', 'JLINK', 'CUBEPROGRAMMER', 'CUBE') -or (Test-Path -LiteralPath $saved -PathType Leaf)) { $choice = $saved }
    }
    if (-not $choice) {
        $hexCount = @(Get-ChildItem -LiteralPath $CurrentDir -File -Filter '*.hex').Count
        if ($hexCount -gt 1 -and (@($cubePaths).Count -gt 0 -or $jlinkPath)) { return $null }
        if (@($cubePaths).Count -gt 0) { $choice = @($cubePaths)[0] }
        elseif ($jlinkPath) { $choice = 'JLINK' }
        else { $choice = 'OPENOCD' }
    }
    $exe = switch ($choice) {
        'OPENOCD' { $OpenOcdExe }
        'JLINK' { $jlinkPath }
        { $_ -in @('CUBE', 'CUBEPROGRAMMER') } { @($cubePaths) | Select-Object -First 1 }
        default { $choice }
    }
    if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) { return $exe }
    return $null
}

function Show-EnvironmentInfo {
    $jLinkEntries = @()
    try { $jLinkEntries = @(Get-JLinkProbes) } catch { Write-Warn $_.Exception.Message }
    Write-Step '1' (T 'InfoEnvironment')
    Write-Info "stm32-flasher: $VERSION"
    Write-Info "Windows: $([Environment]::OSVersion.VersionString)"
    Write-Info "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Info "$(T 'InfoDirectory'): $CurrentDir"
    Write-Step '2' (T 'InfoTools')
    $cubePaths = @(Find-CubeProgrammerCli)
    $jlinkPath = Find-JLinkExe
    $activeTool = Get-InfoEnginePath $cubePaths $jlinkPath
    $toolPaths = @($cubePaths, $jlinkPath, (Find-StInfoExe))
    $openCmd = Get-Command openocd.exe -ErrorAction SilentlyContinue
    if ($openCmd) { $toolPaths += $openCmd.Source }
    if (Test-Path -LiteralPath $OpenOcdExe) { $toolPaths += $OpenOcdExe }
    if ($activeTool) { $toolPaths += $activeTool }
    $toolPaths = @($toolPaths | ForEach-Object { $_ } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $toolPaths.Count) { Write-Info (T 'InfoNone') }
    foreach ($path in $toolPaths) {
        $version = Get-ToolVersion $path
        $marker = if ($activeTool -and $path -ieq $activeTool) { '*' } else { ' ' }
        Write-Info "$marker $path | $version"
    }
    if ($activeTool) { Write-Info (T 'InfoActiveTool') } else { Write-Info (T 'InfoToolPending') }
    Write-Step '3' (T 'InfoSaved')
    foreach ($name in @('.flash_engine', '.probe_type', '.stlink_serial', '.jlink_serial', '.jlink_device', '.openocd_target')) {
        $path = Join-Path $CurrentDir $name
        if (Test-Path -LiteralPath $path) { Write-Info "${name}: $((Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim())" }
    }
    Write-Step '4' (T 'InfoUsb')
    foreach ($reader in @('Get-UsbStLinkProbes')) {
        try {
            $entries = @(& $reader)
            foreach ($entry in $entries) { Write-Info "$($entry.Type) | $($entry.Serial) | $($entry.Family)" }
        } catch { Write-Warn $_.Exception.Message }
    }
    foreach ($entry in $jLinkEntries) { Write-Info "$($entry.Type) | $($entry.Serial) | $($entry.Family)" }
    Write-Step '5' (T 'InfoFirmware')
    $firmwareFiles = @(Get-ChildItem -LiteralPath $CurrentDir -File -Filter '*.hex' | Sort-Object Name)
    if (-not $firmwareFiles.Count) { Write-Info (T 'InfoNone') }
    foreach ($firmware in $firmwareFiles) {
        $checksumPath = Find-Sha256File $firmware.FullName
        $checksumName = if ($checksumPath) { Split-Path -Leaf $checksumPath } else { T 'InfoNone' }
        Write-Info "$($firmware.Name) | $(T 'InfoFileSize'): $($firmware.Length) $(T 'InfoBytes') | $(T 'InfoChecksum'): $checksumName"
    }
}

function ConvertTo-MemoryNumber([string]$value) {
    if ($value -match '^0[xX][0-9a-fA-F]+$') { return [Convert]::ToUInt64($value.Substring(2), 16) }
    if ($value -match '^\d+$') { return [Convert]::ToUInt64($value, 10) }
    throw "Invalid memory value: $value"
}

function New-IntelHexRecord([int]$offset, [int]$type, [byte[]]$data) {
    $sum = $data.Length + ($offset -shr 8) + ($offset -band 255) + $type
    $body = '{0:X2}{1:X4}{2:X2}' -f $data.Length, $offset, $type
    foreach ($b in $data) { $sum += $b; $body += $b.ToString('X2') }
    return ':' + $body + ((256 - ($sum -band 255)) -band 255).ToString('X2')
}

function Write-IntelHex([string]$binaryPath, [string]$hexPath, [uint64]$baseAddress) {
    $bytes = [IO.File]::ReadAllBytes($binaryPath)
    if (-not $bytes.Length -or $baseAddress + $bytes.Length -gt 4294967296) { throw 'Invalid Intel HEX range' }
    $stream = [IO.File]::Open($hexPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = New-Object IO.StreamWriter($stream, [Text.Encoding]::ASCII)
    try {
        $lastUpper = -1
        $pos = 0
        while ($pos -lt $bytes.Length) {
            $addressValue = $baseAddress + $pos
            $upper = [int]($addressValue -shr 16)
            $offset = [int]($addressValue -band 65535)
            if ($upper -ne $lastUpper) {
                $writer.WriteLine((New-IntelHexRecord 0 4 ([byte[]]@(($upper -shr 8), ($upper -band 255)))))
                $lastUpper = $upper
            }
            $count = [Math]::Min(16, [Math]::Min($bytes.Length - $pos, 65536 - $offset))
            $writer.WriteLine((New-IntelHexRecord $offset 0 ([byte[]]$bytes[$pos..($pos + $count - 1)])))
            $pos += $count
        }
        $writer.WriteLine(':00000001FF')
    } finally { $writer.Dispose() }
}

function Invoke-ReadTool($exe, $arguments) {
    $prefix = Join-Path $CurrentDir ('.flash_read_' + [guid]::NewGuid().ToString('N'))
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$prefix.stdout" -RedirectStandardError "$prefix.stderr"
        $out = Get-Content -LiteralPath "$prefix.stdout" -Raw -ErrorAction SilentlyContinue
        $err = Get-Content -LiteralPath "$prefix.stderr" -Raw -ErrorAction SilentlyContinue
        $log = @($out, $err) -join "`n"
        if ($SelectedEngine -eq 'OPENOCD' -and $SelectedProbeSerial -and $proc.ExitCode -ne 0 -and $log -match 'No device matches the serial string') {
            $plain = "`"$(Get-OpenOcdSerialCommand $SelectedProbeSerial plain)`""
            $index = [Array]::IndexOf($arguments, $plain)
            if ($index -ge 0) {
                $retry = @($arguments)
                $retry[$index] = "`"$(Get-OpenOcdSerialCommand $SelectedProbeSerial bytes)`""
                return Invoke-ReadTool $exe $retry
            }
        }
        return [PSCustomObject]@{ ExitCode = $proc.ExitCode; Log = $log }
    } finally { Remove-Item -LiteralPath "$prefix.stdout", "$prefix.stderr" -ErrorAction SilentlyContinue }
}

function Get-ReadSizeFromLog($parser, $log, $deviceName) {
    if ($parser -eq 'JLINK' -and $deviceName -match '^STM32F10[12357]') {
        if ($log -match '(?im)^\s*1FFFF7E0\s*=\s*([0-9A-F]{4})\b') {
            $kb = [Convert]::ToUInt32($Matches[1], 16)
            if ($deviceName -match '^STM32F103.8' -and $kb -ne 64) {
                Write-Warn "$(T 'BackupSizeConflict') ($kb KiB / 64 KiB)"
                return 0
            }
            if ($kb -gt 0 -and $kb -le 1024) { return [uint64]$kb * 1024 }
        }
    } elseif ($parser -eq 'CUBEPROGRAMMER') {
        if ($log -match '(?im)^\s*Flash size\s*:\s*(\d+)\s*KBytes') { return [uint64]$Matches[1] * 1024 }
    } elseif ($parser -eq 'OPENOCD') {
        # Only a single contiguous bank can be inferred without additional memory-map handling.
        $banks = @([regex]::Matches($log, '(?m)^FLASH_BACKUP_BANK (\d+) (\d+)\s*$'))
        if ($banks.Count -eq 1 -and [uint64]$banks[0].Groups[1].Value -eq 134217728) {
            return [uint64]$banks[0].Groups[2].Value
        }
    }
    return 0
}

function Test-BackupReadLog($parser, $log) {
    if ($log -match '(?im)^\s*(Error:|ERROR:|Cannot read|Failed to read)') { return $false }
    switch ($parser) {
        'JLINK' { return $log -match '(?im)^Reading \d+ bytes from addr [^\r\n]+O\.K\.' }
        'OPENOCD' { return $log -match '(?m)^FLASH_BACKUP_COMPLETE\s*$' }
        default { return $log -match '(?im)^\s*Data read successfully\s*$' }
    }
}

function Get-BackupFileName($deviceName, $log, $probeId, [uint64]$byteCount, [DateTime]$timestamp) {
    $idText = $probeId
    if ($log -match '(?im)^\s*Device ID\s*:\s*(0x[0-9a-f]+)\b') {
        $idText = $Matches[1]
    } elseif ($log -match '(?i)device id(?:code)?\s*=\s*(0x[0-9a-f]+)\b') {
        $idText = $Matches[1]
    } elseif ($log -match '(?im)^\s*E0042000\s*=\s*([0-9a-f]{8})\b') {
        $idText = '0x' + $Matches[1]
    }
    $idLabel = 'IDunknown'
    if ($idText -match '^0x[0-9a-fA-F]{1,8}$') {
        # DEV_ID is the lower 12 bits; the upper bits include the silicon revision.
        $deviceId = [Convert]::ToUInt32($idText.Substring(2), 16) -band 0xFFF
        if ($deviceId -ne 0 -and $deviceId -ne 0xFFF) { $idLabel = 'ID0x{0:X3}' -f $deviceId }
    }
    $name = if ($deviceName) { $deviceName -replace '[^a-zA-Z0-9_-]', '_' } else { 'STM32' }
    $kilobytes = [uint64][Math]::Ceiling($byteCount / 1024.0)
    return '{0}_{1}_{2}_{3}K.hex' -f $name, $timestamp.ToString('yyyyMMdd_HHmmss'), $idLabel, $kilobytes
}

# ══════════════════════════════════════════════════════════════════════════════
#  Пути и окружение
# ══════════════════════════════════════════════════════════════════════════════

$CurrentDir     = (Get-Location).Path
$ToolDir        = Join-Path $CurrentDir ".tools"
$HistoryDir     = Join-Path $CurrentDir ".history"
$LogFile        = Join-Path $CurrentDir "flash_log.txt"
$HtmlReport     = Join-Path $CurrentDir "report.html"

if ($ResetConfig -or $Clean) {
    $cleanupNames = @('.flash_engine', '.probe_type', '.stlink_serial', '.jlink_serial', '.jlink_device', '.openocd_target')
    if ($Clean) {
        $cleanupNames += @('.jlink_flash.jlink', 'flash_log.txt', 'flash_log.txt.stdout', 'flash_log.txt.stderr', 'report.html', '.history', '.tools/stlink', '.tools/stlink.zip', '.tools/openocd.zip', '.tools/xpack-openocd-0.12.0-3')
        $cleanupNames += @(Get-ChildItem -LiteralPath $CurrentDir -Force -File | Where-Object { $_.Name -match '^\.flash_(backup|read)_[0-9a-f]{32}\.(bin|hex|sha256|stdout|stderr)$' } | Select-Object -ExpandProperty Name)
    }
    $root = [IO.Path]::GetFullPath($CurrentDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($name in $cleanupNames) {
        $path = [IO.Path]::GetFullPath((Join-Path $CurrentDir $name))
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid cleanup path: $path" }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        # Never follow junctions or symbolic links during recursive cleanup.
        $items = @((Get-Item -LiteralPath $path -Force))
        $parent = Split-Path -Parent $path
        while ($parent -and $parent.Length -ge $root.TrimEnd('\').Length) {
            $items += Get-Item -LiteralPath $parent -Force
            $parent = Split-Path -Parent $parent
        }
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Linked cleanup path: $path" }
        if (Test-Path -LiteralPath $path -PathType Container) {
            $linked = Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
            if ($linked) { throw "Linked cleanup content: $path" }
        }
        Write-Host "   $path"
        if (-not $DryRun) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
    if ($DryRun) { Write-Info (T 'CleanupPreview') } else { Write-Ok (T 'CleanupDone') }
    exit 0
}

$OpenOcdUrl     = "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-3/xpack-openocd-0.12.0-3-win32-x64.zip"
$OpenOcdZip     = Join-Path $ToolDir "openocd.zip"
$OpenOcdExe     = Join-Path $ToolDir "xpack-openocd-0.12.0-3\bin\openocd.exe"
$OpenOcdScripts = Join-Path $ToolDir 'xpack-openocd-0.12.0-3/openocd/scripts'
$installedOpenOcd = Find-OpenOcdInstallation $OpenOcdExe
if ($installedOpenOcd) {
    $OpenOcdExe = $installedOpenOcd.Exe
    $OpenOcdScripts = $installedOpenOcd.Scripts
}
$StLinkUrl      = "https://github.com/stlink-org/stlink/releases/download/v1.8.0/stlink-1.8.0-win32.zip"
if ($Info) {
    Show-EnvironmentInfo
    if (-not $ProbeTarget) { exit 0 }
}
$SelectedProbeSerial = ""
$SelectedProbeInfo = $null
$SelectedProbeType = "STLINK"
$ProbeSpecified = [bool]$Probe
if ($Probe) {
    switch -Regex ($Probe.Trim()) {
        '^(?i:STLINK|ST-LINK|SWD)$' { $SelectedProbeType = "STLINK"; break }
        '^(?i:JLINK|J-LINK)$'       { $SelectedProbeType = "JLINK"; break }
        default {
            if ($NoFirmware) { throw (T 'InvalidProbe') }
            Write-Warn (T "InvalidProbe")
            $SelectedProbeType = "STLINK"
        }
    }
}

$PsVerStr = $PSVersionTable.PSVersion.ToString()
$WinInfo = ""
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue; if ($os) { $WinInfo = "$($os.Caption) (Build $($os.BuildNumber))" } } catch {}
if (-not $WinInfo) { $WinInfo = [System.Environment]::OSVersion.VersionString }
$OperatorName = $env:USERNAME
$UserAccount = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
$MachineName = $env:COMPUTERNAME
$NetworkHostName = $MachineName
try {
    $hostEntry = [System.Net.Dns]::GetHostEntry($MachineName)
    if ($hostEntry -and $hostEntry.HostName) { $NetworkHostName = $hostEntry.HostName }
} catch {}

# ══════════════════════════════════════════════════════════════════════════════
#  1. Выбор .hex
# ══════════════════════════════════════════════════════════════════════════════

if (-not $NoFirmware) { Write-Step "1" (T "StepSearchHex") }
$TargetHex = ""
$HexName   = ""
$AutoFlash = $false

if ($NoFirmware) {
    $AutoFlash = $true
    $operationLabel = if ($Backup) { T 'BackupName' } elseif ($Info) { T 'InfoTarget' } else { T 'EraseName' }
    Write-Step "1" $operationLabel
} else {
if ($HexFile) {
    if ($HexFile -match '(?i)\.hex$') {
        $TargetHex = $HexFile
        $HexName = Split-Path -Leaf $HexFile
        $AutoFlash = $true
        Write-Info "$(T 'Selected')$HexName"
    } else {
        Write-Warn "$(T 'InvalidHexFile')$HexFile"
        $HexFile = ""
    }
}

if (-not $TargetHex) {
    $HexFiles = @(Get-ChildItem -LiteralPath $CurrentDir -Filter "*.hex" -ErrorAction SilentlyContinue)
    if ($HexFiles.Count -eq 0) { Write-Err (T "ErrNoHex"); Start-Sleep -Seconds 3; exit 1 }

    if ($HexFiles.Count -eq 1) {
        $TargetHex = $HexFiles[0].FullName
        $HexName   = $HexFiles[0].Name
        $AutoFlash = $true
    } else {
        Write-Host "   $(T 'ListAvailable')"
        $i = 1; foreach ($f in $HexFiles) { Write-Host "     [$i] $($f.Name)"; $i++ }
        $choice = Read-Host "`n   $(T 'PromptChoose')"
        $parsedChoice = 0
        if (-not [int]::TryParse($choice, [ref]$parsedChoice)) { Write-Err (T "ErrBadChoice"); Start-Sleep -Seconds 3; exit 1 }
        $idx = $parsedChoice - 1
        if ($idx -lt 0 -or $idx -ge $HexFiles.Count) { Write-Err (T "ErrBadChoice"); Start-Sleep -Seconds 3; exit 1 }

        $TargetHex = $HexFiles[$idx].FullName
        $HexName   = $HexFiles[$idx].Name
    }
    Write-Info "$(T 'Selected')$HexName"
}

$BuildType = if ($HexName -match 'Debug') { "Debug" } elseif ($HexName -match 'Release') { "Release" } else { "Unknown" }

# ══════════════════════════════════════════════════════════════════════════════
#  2. Build Info + CHANGELOG
# ══════════════════════════════════════════════════════════════════════════════

$BuildInfoPath = Join-Path $CurrentDir "build_info_$BuildType.md"
$BuildInfo     = Parse-BuildInfo $BuildInfoPath
$ChangelogPath = Join-Path $CurrentDir "CHANGELOG.md"
$ChangelogContent = if (Test-Path -LiteralPath $ChangelogPath) { Get-Content -LiteralPath $ChangelogPath -Raw -Encoding UTF8 } else { "" }
}
if ($NoFirmware) {
    $BuildType = ""
    $BuildInfo = @{}
    $ChangelogContent = ""
}
$HashCheckPerformed = $false
$HashCheckOk = $false
$HashExpected = ""
$HashActual = ""
$HashSource = ""
$HashSpecPath = ""
$PreflightFailed = $false
$PreflightMessage = ""
$PreflightLog = ""
$PreflightDuration = [TimeSpan]::Zero

if (-not $NoFirmware) { try {
    $hashSourceFile = Find-Sha256File $TargetHex
    if ($Sha256) {
        $HashExpected = (Parse-Sha256Value $Sha256)
        if ($HashExpected) {
            $HashSource = T "IntegritySourceCli"
            $HashCheckPerformed = $true
        } else {
            Write-Warn "$(T 'IntegrityInvalid'): $Sha256"
        }
    } elseif ($hashSourceFile) {
        $HashSpecPath = $hashSourceFile
        $HashExpected = Parse-Sha256Value (Get-Content -LiteralPath $hashSourceFile -Raw -Encoding UTF8)
        if ($HashExpected) {
            $HashSource = "$(T 'IntegritySourceFile'): $([System.IO.Path]::GetFileName($hashSourceFile))"
            $HashCheckPerformed = $true
            Write-Info "$(T 'IntegrityFound'): $([System.IO.Path]::GetFileName($hashSourceFile))"
        } else {
            Write-Warn "$(T 'IntegrityInvalid'): $([System.IO.Path]::GetFileName($hashSourceFile))"
        }
    }

    if ($HashCheckPerformed) {
        $PreflightTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $HashActual = (Get-FileHash -LiteralPath $TargetHex -Algorithm SHA256).Hash.ToUpperInvariant()
        $PreflightTimer.Stop()
        $PreflightDuration = $PreflightTimer.Elapsed
        $HashCheckOk = $HashActual -eq $HashExpected
        if ($HashCheckOk) {
            Write-Ok (T "IntegrityPassed")
        } else {
            $PreflightFailed = $true
            $PreflightMessage = T "IntegrityAbort"
            Write-Err $PreflightMessage
            $PreflightLog = @(
                $PreflightMessage,
                "$(T 'IntegritySource'): $HashSource",
                "$(T 'IntegrityExpected'): $HashExpected",
                "$(T 'IntegrityActual'): $HashActual"
            ) -join "`n"
        }
    }
} catch {
    Write-Warn $_.Exception.Message
} }

# ══════════════════════════════════════════════════════════════════════════════
#  3. Выбор движка (STM32CubeProgrammer vs OpenOCD)
# ══════════════════════════════════════════════════════════════════════════════

if (-not $PreflightFailed) {
Write-Step "2" (T "StepSelectEngine")

# Erase always resolves the currently attached probe, never a stale saved serial.
if ($FreshProbeSelection -and -not $DryRun) {
    $connected = @()
    $directJLink = Test-IsJLinkEngine $SelectedEngine
    if (-not $directJLink -and $SelectedProbeType -ne 'JLINK') {
        $stExe = Find-StInfoExe
        if ($stExe) {
            $stProbes = Get-StInfoProbeInfo $stExe
            foreach ($entry in $stProbes.Entries) {
                $connected += [PSCustomObject]@{ Serial = $entry.Serial; Family = $entry.Family; Type = 'STLINK' }
            }
        }
    }
    if ($directJLink -or (-not $ProbeSpecified -and $SelectedEngine -ne 'OPENOCD') -or $SelectedProbeType -eq 'JLINK') {
        $connected += @(Get-JLinkProbes)
    }
    if ($Serial) {
        $connected = @($connected | Where-Object { $_.Serial -eq $Serial })
        if ($connected.Count -eq 0 -and $ProbeSpecified) {
            $connected = @([PSCustomObject]@{ Serial = $Serial; Family = ''; Type = $SelectedProbeType })
        }
    }
    if ($connected.Count -eq 0) { throw (T 'NoDebugger') }
    $chosenProbe = Select-ConnectedProbe $connected
    $Serial = $chosenProbe.Serial
    $SelectedProbeType = $chosenProbe.Type
    $ProbeSpecified = $true
    Write-Info "$(T 'SelectedProbe'): $SelectedProbeType $Serial"
}

$EngineCfgPath = Join-Path $CurrentDir ".flash_engine"
# $SelectedEngine may already be set from CLI parameter

if (-not $SelectedEngine -and (Test-Path -LiteralPath $EngineCfgPath)) {
    $SavedEngine = (Get-Content -LiteralPath $EngineCfgPath -TotalCount 1).Trim()
    if ($SavedEngine -eq "OPENOCD" -or $SavedEngine -eq "JLINK" -or $SavedEngine -eq "CUBEPROGRAMMER" -or $SavedEngine -eq "CUBE" -or (Test-Path -LiteralPath $SavedEngine)) {
        $SelectedEngine = $SavedEngine
    }
}
if ($FreshProbeSelection -and -not $DryRun -and -not $Engine) {
    if (($SelectedProbeType -eq 'JLINK' -and $SelectedEngine -eq 'OPENOCD') -or
        ($SelectedProbeType -eq 'STLINK' -and (Test-IsJLinkEngine $SelectedEngine))) {
        $SelectedEngine = ''
    }
}

if (-not $SelectedEngine) {
    Write-Info (T "SearchCubeProg")
    $FoundCli = Find-CubeProgrammerCli
    Write-Info (T "SearchJLink")
    $FoundJLink = Find-JLinkExe

    $Opts = @()
    $Opts += @{ Label = "$(T 'EngineOpenOCD')"; Value = "OPENOCD" }
    foreach ($cli in $FoundCli) { $Opts += @{ Label = "$(T 'EngineCubeProg') ($cli)"; Value = $cli } }
    if ($FoundJLink -and (-not $NoFirmware -or $SelectedProbeType -eq 'JLINK')) { $Opts += @{ Label = "$(T 'EngineJLink') ($FoundJLink)"; Value = "JLINK" } }

    if ($Opts.Count -eq 1) {
        $SelectedEngine = "OPENOCD"
    } elseif ($AutoFlash) {
        $PreferredCubeProg = $Opts | Where-Object { $_.Value -ne "OPENOCD" } | Select-Object -First 1
        if ($PreferredCubeProg) { $SelectedEngine = $PreferredCubeProg.Value } else { $SelectedEngine = "OPENOCD" }
    } else {
        Write-Host "   $(T 'FoundEngines')" -ForegroundColor Yellow
        for ($k=0; $k -lt $Opts.Count; $k++) { Write-Host "     [$($k+1)] $($Opts[$k].Label)" }
        $ans = Read-Host "   $(T 'PromptChooseEng')"
        $parsedEngineChoice = 0
        if (-not [int]::TryParse($ans, [ref]$parsedEngineChoice)) { $parsedEngineChoice = 1 }
        $idx = $parsedEngineChoice - 1
        if ($idx -ge 0 -and $idx -lt $Opts.Count) { $SelectedEngine = $Opts[$idx].Value } else { $SelectedEngine = "OPENOCD" }
    }
    Save-LaunchSetting $EngineCfgPath $SelectedEngine
}
if ($Engine) { Save-LaunchSetting $EngineCfgPath $SelectedEngine }
if ($NoFirmware -and $SelectedEngine -eq 'OPENOCD' -and $SelectedProbeType -eq 'JLINK') {
    throw 'OpenOCD currently supports ST-Link only. Use -Engine JLINK or CUBEPROGRAMMER.'
}

$StLinkSerialCfgPath = Join-Path $CurrentDir ".stlink_serial"
$JLinkSerialCfgPath = Join-Path $CurrentDir ".jlink_serial"
$ProbeTypeCfgPath = Join-Path $CurrentDir ".probe_type"
$ProbeInfo = $null
if (-not $ProbeSpecified -and (Test-Path -LiteralPath $ProbeTypeCfgPath)) {
    $SavedProbeType = (Get-Content -LiteralPath $ProbeTypeCfgPath -TotalCount 1).Trim()
    if ($SavedProbeType -in @("STLINK", "JLINK")) {
        $SelectedProbeType = $SavedProbeType
    }
}
if ($SelectedProbeType -eq "JLINK") {
    if ($Serial) {
        $SelectedProbeSerial = $Serial
    } elseif (Test-Path -LiteralPath $JLinkSerialCfgPath) {
        $SelectedProbeSerial = (Get-Content -LiteralPath $JLinkSerialCfgPath -TotalCount 1).Trim()
    }
}
if (-not (Test-IsJLinkEngine $SelectedEngine) -and $SelectedProbeType -ne "JLINK") {
try {
    $stInfoExe = Find-StInfoExe
    if ($stInfoExe) {
        $ProbeInfo = Get-StInfoProbeInfo $stInfoExe
    }
} catch {}

if ($ProbeInfo -and $ProbeInfo.Count -gt 0) {
    $CandidateSerial = $null
    if ($Serial) {
        $CandidateSerial = $Serial
    } elseif (-not $FreshProbeSelection -and (Test-Path -LiteralPath $StLinkSerialCfgPath)) {
        $CandidateSerial = (Get-Content -LiteralPath $StLinkSerialCfgPath -TotalCount 1).Trim()
    }

    if ($CandidateSerial) {
        $SelectedProbeInfo = $ProbeInfo.Entries | Where-Object { $_.Serial -eq $CandidateSerial } | Select-Object -First 1
        if ($SelectedProbeInfo) {
            $SelectedProbeSerial = $SelectedProbeInfo.Serial
        } elseif ($Serial) {
            if ($FreshProbeSelection) { throw (T 'InvalidSerial') }
            Write-Warn (T "InvalidSerial")
        }
    }

    if (-not $SelectedProbeInfo -and $ProbeInfo.Count -gt 1) {
        for ($k = 0; $k -lt $ProbeInfo.Entries.Count; $k++) {
            $entry = $ProbeInfo.Entries[$k]
            $familyLabel = if ($entry.Family) { $entry.Family } else { "?" }
            Write-Host "     [$($k+1)] $(T 'ProbeSerial'): $($entry.Serial) | $(T 'ProbeFamily'): $familyLabel"
        }
        $ans = Read-Host "   $(T 'PromptChooseProbe')"
        $parsedProbeChoice = 0
        if (-not [int]::TryParse($ans, [ref]$parsedProbeChoice)) { Write-Err (T "ErrBadChoice"); Start-Sleep -Seconds 3; exit 1 }
        $idx = $parsedProbeChoice - 1
        if ($idx -lt 0 -or $idx -ge $ProbeInfo.Entries.Count) { Write-Err (T "ErrBadChoice"); Start-Sleep -Seconds 3; exit 1 }
        $SelectedProbeInfo = $ProbeInfo.Entries[$idx]
        $SelectedProbeSerial = $SelectedProbeInfo.Serial
    } elseif (-not $SelectedProbeInfo -and $ProbeInfo.Count -eq 1) {
        $SelectedProbeInfo = $ProbeInfo.Entries[0]
        $SelectedProbeSerial = $SelectedProbeInfo.Serial
    }

    if ($SelectedProbeSerial) {
        Write-Info "$(T 'SelectedProbe'): $SelectedProbeSerial"
        Save-LaunchSetting $StLinkSerialCfgPath $SelectedProbeSerial
    }
}

if (-not $ProbeSpecified -and $SelectedProbeType -eq "STLINK" -and -not $SelectedProbeSerial -and (Find-JLinkExe)) {
    $SelectedProbeType = "JLINK"
    if (Test-Path -LiteralPath $JLinkSerialCfgPath) {
        $SelectedProbeSerial = (Get-Content -LiteralPath $JLinkSerialCfgPath -TotalCount 1).Trim()
    }
    Write-Info "$(T 'SelectedProbe'): J-Link"
}
}
if (-not (Test-IsJLinkEngine $SelectedEngine)) {
    Save-LaunchSetting $ProbeTypeCfgPath $SelectedProbeType
}
if ($SelectedProbeType -eq "JLINK" -and $SelectedProbeSerial) {
    Save-LaunchSetting $JLinkSerialCfgPath $SelectedProbeSerial
}
}

# ══════════════════════════════════════════════════════════════════════════════
#  4. Подготовка и Прошивка
# ══════════════════════════════════════════════════════════════════════════════

$LogStd = "$LogFile.stdout"
$LogErr = "$LogFile.stderr"
$ExePath = ""
$ExeArgs = @()
$RetryArgsWithoutSerial = @()
$JLinkScript = ""
$SelectedJLinkDevice = ""
$SelectedJLinkSerial = ""

if ($PreflightFailed) {
    $process = [PSCustomObject]@{ ExitCode = 2 }
    $LogContent = if ($PreflightLog) { $PreflightLog } else { T "IntegrityAbort" }
    $OperationDuration = $PreflightDuration.ToString("hh\:mm\:ss\.fff")
} elseif ($SelectedEngine -eq "OPENOCD") {
    Write-Step "3" (T "StepPrepareOpenOCD")
    if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $OpenOcdExe))) {
        if ($Info) { throw 'OpenOCD is not installed in the working directory.' }
        Write-Warn (T "DownloadOpenOCD")
        New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
        Invoke-Download $OpenOcdUrl $OpenOcdZip
        Expand-Archive -Path $OpenOcdZip -DestinationPath $ToolDir -Force
        Remove-Item -LiteralPath $OpenOcdZip -ErrorAction SilentlyContinue
    }
    if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $OpenOcdScripts))) {
        $foundS = Get-ChildItem -Path (Join-Path $ToolDir "xpack-openocd-0.12.0-3") -Recurse -Filter "stlink.cfg" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundS) { $OpenOcdScripts = Split-Path -Parent $foundS.DirectoryName }
    }

    # Поиск TargetCfg
    $TargetCfg = ""
    $SavedTargetCfg = Join-Path $CurrentDir ".openocd_target"
    if (-not $FreshProbeSelection -and (Test-Path -LiteralPath $SavedTargetCfg)) { $TargetCfg = (Get-Content -LiteralPath $SavedTargetCfg -TotalCount 1).Trim() }
    if ($Target) { $TargetCfg = $Target }
    if ($TargetCfg) {
        $TargetCfgPath = Join-Path $OpenOcdScripts ($TargetCfg -replace '/','\')
        if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $TargetCfgPath -PathType Leaf))) {
            Write-Warn (T 'InvalidTarget')
            $TargetCfg = ""
        }
    }

    if (-not $TargetCfg) {
        Write-Info (T "SearchStLinkInfo")
        try {
            if (-not $ProbeInfo) {
                $stInfoExe = if ($Info) { Find-StInfoExe } else { Ensure-StInfoExe }
                $ProbeInfo = Get-StInfoProbeInfo $stInfoExe
            }
            Write-Info "$(T 'ProbeFoundCount'): $($ProbeInfo.Count)"
            $probeEntry = if ($SelectedProbeInfo) { $SelectedProbeInfo } elseif ($ProbeInfo.Count -eq 1) { $ProbeInfo.Entries[0] } else { $null }
            if ($probeEntry -and $probeEntry.TargetCfg) {
                Write-Info "$(T 'ProbeChipId'): $($probeEntry.ChipIdHex)"
                $TargetCfg = $probeEntry.TargetCfg
                Write-Info "$(T 'TargetFoundProbe'): $($probeEntry.ChipIdHex) -> $($probeEntry.Family) -> $($probeEntry.TargetCfg)"
            } elseif ($probeEntry -and $probeEntry.ChipIdHex) {
                Write-Info "$(T 'ProbeChipId'): $($probeEntry.ChipIdHex)"
                Write-Warn "$(T 'ProbeNoTarget'): $($probeEntry.Family)"
            } elseif ($probeEntry) {
                Write-Warn (T "ProbeNoChipId")
            } elseif ($ProbeInfo.Count -gt 1) {
                Write-Warn (T "ProbeSkippedMulti")
            }
        } catch {
            Write-Warn (T "ProbeUnavailable")
        }
    }

    if (-not $TargetCfg) {
        $Roots = @( $CurrentDir, (Split-Path $CurrentDir -Parent -ErrorAction SilentlyContinue), (Split-Path (Split-Path $CurrentDir -Parent -ErrorAction SilentlyContinue) -Parent -ErrorAction SilentlyContinue) ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($r in $Roots) {
            $ioc = Get-ChildItem -Path $r -Filter "*.ioc" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ioc) {
                if ((Get-Content -LiteralPath $ioc.FullName -ErrorAction SilentlyContinue) -match "^Mcu\.Family=STM32(.+)$") {
                    $TargetCfg = "target/stm32$($Matches[1].ToLower())x.cfg"; Write-Info (T "TargetFoundIoc"); break
                }
            }
        }
    }
    if (-not $TargetCfg) {
        if ($HexName -match "(?i)stm32([fghlu]\d)") { $TargetCfg = "target/stm32$($Matches[1].ToLower())x.cfg" }
    }
    if (-not $TargetCfg) {
        Write-Host "   [?] $(T 'NoTargetDef')" -ForegroundColor Yellow -NoNewline
        $TargetCfg = Read-Host
    }
    if ($TargetCfg) {
        $TargetCfgPath = Join-Path $OpenOcdScripts ($TargetCfg -replace '/','\')
        if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $TargetCfgPath -PathType Leaf))) {
            Write-Err (T 'InvalidTarget')
            Start-Sleep -Seconds 3
            exit 1
        }
    }
    Save-LaunchSetting $SavedTargetCfg $TargetCfg

    Write-Host "   $(T 'EngineOpenOCDCfg')$TargetCfg)" -ForegroundColor Cyan
    $ExePath = $OpenOcdExe
    $TclCmd = "`"program {$TargetHex} verify reset exit`""
    if ($Erase) {
        $TclCmd = '"init; reset init; set banks [flash list]; if {[llength $banks] == 0} {error {No flash banks}}; set banknum 0; foreach bank $banks {flash erase_sector $banknum 0 last; incr banknum}; echo {FLASH_ERASE_COMPLETE}; shutdown"'
    }
    $ExeArgs = @("-s", "`"$OpenOcdScripts`"", "-f", "interface/stlink.cfg")
    if ($SelectedProbeSerial) {
        $ExeArgs += @("-c", "`"$(Get-OpenOcdSerialCommand $SelectedProbeSerial plain)`"")
    }
    $ExeArgs += @("-f", $TargetCfg, "-c", $TclCmd)

} elseif (Test-IsJLinkEngine $SelectedEngine) {
    Write-Step "3" (T "StepPrepareJLink")
    $JLinkExe = if ($SelectedEngine -ieq "JLINK") { Find-JLinkExe } else { $SelectedEngine }
    if (-not $JLinkExe -or -not (Test-Path -LiteralPath $JLinkExe -PathType Leaf)) {
        Write-Err (T "InvalidEngine")
        Start-Sleep -Seconds 3
        exit 1
    }

    $JLinkDeviceCfgPath = Join-Path $CurrentDir ".jlink_device"
    if ($Device) {
        $SelectedJLinkDevice = $Device.Trim()
    } elseif (Test-Path -LiteralPath $JLinkDeviceCfgPath) {
        $SelectedJLinkDevice = (Get-Content -LiteralPath $JLinkDeviceCfgPath -TotalCount 1).Trim()
    }
    if (-not $SelectedJLinkDevice) {
        Write-Host "   [?] $(T 'PromptJLinkDevice'): " -ForegroundColor Yellow -NoNewline
        $SelectedJLinkDevice = (Read-Host).Trim()
    }
    if (-not $SelectedJLinkDevice) {
        Write-Err (T "InvalidJLinkDevice")
        Start-Sleep -Seconds 3
        exit 1
    }
    Save-LaunchSetting $JLinkDeviceCfgPath $SelectedJLinkDevice

    $JLinkSerialCfgPath = Join-Path $CurrentDir ".jlink_serial"
    if ($Serial) {
        $SelectedJLinkSerial = $Serial
    } elseif (Test-Path -LiteralPath $JLinkSerialCfgPath) {
        $SelectedJLinkSerial = (Get-Content -LiteralPath $JLinkSerialCfgPath -TotalCount 1).Trim()
    }

    Write-Host "   $(T 'EngineJLinkName')" -ForegroundColor Cyan
    Write-Info "$(T 'JLinkDevice'): $SelectedJLinkDevice"
    if ($SelectedJLinkSerial) {
        Write-Info "$(T 'ProbeSerial'): $SelectedJLinkSerial"
        Save-LaunchSetting $JLinkSerialCfgPath $SelectedJLinkSerial
    }
    Save-LaunchSetting (Join-Path $CurrentDir '.probe_type') 'JLINK'

    $JLinkScript = Join-Path $CurrentDir ".jlink_flash.jlink"
    $scriptLines = @(
        "EoE 1",
        "r",
        "h",
        "loadfile `"$TargetHex`"",
        "r",
        "g",
        "q"
    )
    if ($Erase) { $scriptLines = @('EoE 1', 'r', 'h', 'erase', 'q') }
    if ($Backup -or $Info) { $scriptLines = @('EoE 1', 'connect', 'q') }
    if (-not $DryRun) { Set-Content -LiteralPath $JLinkScript -Value ($scriptLines -join "`r`n") -Encoding ASCII }

    $ExePath = $JLinkExe
    $ExeArgs = @("-device", $SelectedJLinkDevice, "-if", "swd", "-speed", "4000", "-nogui", "1")
    $RetryArgsWithoutSerial = @("-device", $SelectedJLinkDevice, "-if", "swd", "-speed", "4000", "-nogui", "1", "-CommandFile", "`"$JLinkScript`"")
    if ($SelectedJLinkSerial) { $ExeArgs += @("-usb", $SelectedJLinkSerial) }
    $ExeArgs += @("-CommandFile", "`"$JLinkScript`"")

} else {
    Write-Step "3" (T "StepPrepareCubeProg")
    Write-Host "   $(T 'EngineCubeProgName')" -ForegroundColor Cyan
    Write-Info "$(T 'ProbeType'): $SelectedProbeType"
    if ($SelectedProbeType -ne "JLINK") { Write-Info (T "AutoDetectMcu") }
    $ExePath = if (($SelectedEngine -ieq "CUBEPROGRAMMER") -or ($SelectedEngine -ieq "CUBE")) { Find-CubeProgrammerCli | Select-Object -First 1 } else { $SelectedEngine }
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        Write-Err (T "InvalidEngine")
        Start-Sleep -Seconds 3
        exit 1
    }
    # Ключи: -c (подключение), -w (прошивка), -v (верификация), -rst (сброс)
    $ConnectionPort = if ($SelectedProbeType -eq "JLINK") { "JLINK" } else { "SWD" }
    $ConnectionArgs = if ($SelectedProbeSerial) { "port=$ConnectionPort sn=$SelectedProbeSerial" } else { "port=$ConnectionPort" }
    $ExeArgs = @("-c", $ConnectionArgs, "-w", $TargetHex, "-v")
    $RetryArgsWithoutSerial = @("-c", "port=$ConnectionPort", "-w", $TargetHex, "-v")
    if ($Erase) {
        $ExeArgs = @('-c', $ConnectionArgs, '-e', 'all')
        $RetryArgsWithoutSerial = @('-c', "port=$ConnectionPort", '-e', 'all')
    }
    if ($SelectedProbeType -ne "JLINK" -and -not $NoFirmware) {
        $ExeArgs += "-rst"
        $RetryArgsWithoutSerial += "-rst"
    }
}

$BackupSaved = $false
$ReadOperationHandled = $false
$BackupOutput = ''
$BackupRangeLabel = ''
if ($Backup -or ($Info -and $ProbeTarget)) {
    $ReadOperationHandled = $true
    $readTimer = [Diagnostics.Stopwatch]::StartNew()
    $readLog = ''
    $readKey = if ($SelectedEngine -eq 'OPENOCD') { 'OPENOCD' } elseif (Test-IsJLinkEngine $SelectedEngine) { 'JLINK' } else { 'CUBEPROGRAMMER' }
    $readPrefix = Join-Path $CurrentDir ('.flash_backup_' + [guid]::NewGuid().ToString('N'))
    $binaryPath = "$readPrefix.bin"
    $hexStage = "$readPrefix.hex"
    $shaStage = "$readPrefix.sha256"
    $hexPublished = $false
    try {
        $readAddress = if ($Address) { ConvertTo-MemoryNumber $Address } else { [uint64]134217728 }
        $readSize = if ($Size) { ConvertTo-MemoryNumber $Size } else { [uint64]0 }
        if ($readAddress -gt [uint32]::MaxValue -or ($Size -and ($readSize -eq 0 -or $readSize -gt 67108864 -or $readAddress + $readSize -gt 4294967296))) { throw 'Invalid backup address/size (maximum 64 MiB).' }
        if ($Backup) {
            $name = if ($SelectedJLinkDevice) { $SelectedJLinkDevice } elseif ($SelectedProbeInfo.Family) { $SelectedProbeInfo.Family } else { 'STM32' }
            $backupTimestamp = [DateTime]::Now
            if ($Output) {
                $BackupOutput =
                if ([IO.Path]::IsPathRooted($Output)) { [IO.Path]::GetFullPath($Output) } else { [IO.Path]::GetFullPath((Join-Path $CurrentDir $Output)) }
                if ([IO.Path]::GetExtension($BackupOutput) -ine '.hex') { throw 'Backup output must have a .hex extension.' }
                if ((Test-Path -LiteralPath $BackupOutput) -or (Test-Path -LiteralPath "$BackupOutput.sha256")) { throw "Backup already exists: $BackupOutput" }
            }
        }
        $metadataArgs = @($ExeArgs)
        switch ($readKey) {
            'JLINK' {
                $metadataCommands = @('EoE 1', 'connect')
                if ($Backup -and -not $Size -and $SelectedJLinkDevice -match '^STM32F10[12357]') { $metadataCommands += 'mem16 0x1FFFF7E0 1' }
                $metadataCommands += 'q'
                if (-not $DryRun) { Set-Content -LiteralPath $JLinkScript -Value ($metadataCommands -join "`r`n") -Encoding ASCII }
            }
            'OPENOCD' {
                $metadataArgs[-1] = '"init; set n 0; foreach bank [flash list] {flash probe $n; incr n}; foreach bank [flash list] {echo [format {FLASH_BACKUP_BANK %d %d} [dict get $bank base] [dict get $bank size]]}; shutdown"'
            }
            default { $metadataArgs = @('-c', $ConnectionArgs) }
        }
        if (-not $DryRun -and ($Info -or -not $readSize)) {
            $metadata = Invoke-ReadTool $ExePath $metadataArgs
            $readLog = $metadata.Log
            if ($metadata.ExitCode -ne 0) { throw (T 'BackupFailed') }
            if (-not $readSize -and $readAddress -eq 134217728) { $readSize = Get-ReadSizeFromLog $readKey $readLog $SelectedJLinkDevice }
        }
        if ($Info) {
            if ($DryRun) { Write-Host "$ExePath $($metadataArgs -join ' ')" } else { Write-Host (Normalize-ToolLog $readLog) }
        } else {
            if (-not $readSize) {
                if ($DryRun -or $Silent) { throw 'Specify -Size in bytes: automatic Flash size is unavailable.' }
                $readSize = ConvertTo-MemoryNumber (Read-Host (T 'BackupSize'))
            }
            if ($readSize -eq 0 -or $readSize -gt 67108864 -or $readAddress + $readSize -gt 4294967296) { throw 'Invalid backup range (maximum 64 MiB).' }
            if (-not $Output) {
                $BackupOutput = Join-Path (Join-Path $CurrentDir 'backups') (Get-BackupFileName $name $readLog $SelectedProbeInfo.ChipIdHex $readSize $backupTimestamp)
            }
            $BackupRangeLabel = '0x{0:X8} + {1} bytes' -f $readAddress, $readSize
            Write-Info "$(T 'BackupRange'): $BackupRangeLabel"
            $readArgs = @($ExeArgs)
            switch ($readKey) {
                'JLINK' {
                    $readCommands = @('EoE 1', 'connect', 'h', ('savebin "{0}" 0x{1:X8} 0x{2:X}' -f $binaryPath, $readAddress, $readSize), 'g', 'q')
                    if (-not $Output -and $SelectedJLinkDevice -match '^STM32F10[12357]') {
                        $readCommands = @('EoE 1', 'connect', 'mem32 0xE0042000 1') + $readCommands[2..($readCommands.Count - 1)]
                    }
                    if (-not $DryRun) { Set-Content -LiteralPath $JLinkScript -Value ($readCommands -join "`r`n") -Encoding ASCII }
                }
                'OPENOCD' {
                    $readArgs[-1] = '"init; halt; dump_image {{{0}}} 0x{1:X8} {2}; resume; echo {{FLASH_BACKUP_COMPLETE}}; shutdown"' -f ($binaryPath -replace '\\', '/'), $readAddress, $readSize
                }
                default { $readArgs = @('-c', $ConnectionArgs, '-u', ('0x{0:X8}' -f $readAddress), "$readSize", "`"$binaryPath`"") }
            }
            if ($DryRun) {
                Write-Host "$ExePath $($readArgs -join ' ')"
                if ($readKey -eq 'JLINK') { Write-Host ($readCommands -join "`n") }
                Write-Info $BackupOutput
            } else {
                $result = Invoke-ReadTool $ExePath $readArgs
                $readLog += "`n" + $result.Log
                if ($result.ExitCode -ne 0 -or -not (Test-BackupReadLog $readKey $result.Log) -or -not (Test-Path -LiteralPath $binaryPath) -or (Get-Item -LiteralPath $binaryPath).Length -ne $readSize) { throw (T 'BackupFailed') }
                if (-not $Output) {
                    $BackupOutput = Join-Path (Join-Path $CurrentDir 'backups') (Get-BackupFileName $name $readLog $SelectedProbeInfo.ChipIdHex (Get-Item -LiteralPath $binaryPath).Length $backupTimestamp)
                    if ((Test-Path -LiteralPath $BackupOutput) -or (Test-Path -LiteralPath "$BackupOutput.sha256")) { throw "Backup already exists: $BackupOutput" }
                }
                Write-IntelHex $binaryPath $hexStage $readAddress
                $hash = (Get-FileHash -LiteralPath $hexStage -Algorithm SHA256).Hash.ToLowerInvariant()
                [IO.File]::WriteAllText($shaStage, "$hash *$([IO.Path]::GetFileName($BackupOutput))`r`n", [Text.Encoding]::ASCII)
                New-Item -ItemType Directory -Path (Split-Path -Parent $BackupOutput) -Force | Out-Null
                [IO.File]::Move($hexStage, $BackupOutput)
                $hexPublished = $true
                [IO.File]::Move($shaStage, "$BackupOutput.sha256")
                $BackupSaved = $true
                Write-Info $BackupOutput
            }
        }
        $process = [PSCustomObject]@{ ExitCode = 0 }
    } catch {
        $readLog += "`n" + $_.Exception.Message
        Write-Err $_.Exception.Message
        if ($hexPublished -and -not $BackupSaved) { Remove-Item -LiteralPath $BackupOutput -ErrorAction SilentlyContinue }
        $process = [PSCustomObject]@{ ExitCode = 1 }
    } finally {
        $readTimer.Stop()
        Remove-Item -LiteralPath $binaryPath, $hexStage, $shaStage -ErrorAction SilentlyContinue
        if ($JLinkScript -and -not $DryRun) { Remove-Item -LiteralPath $JLinkScript -ErrorAction SilentlyContinue }
    }
    $OperationDuration = $readTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
    $LogContent = $readLog
    if ($Info -or $DryRun) { exit $process.ExitCode }
}

if (-not $PreflightFailed -and -not $ReadOperationHandled) {
    if ($DryRun -and $Erase) {
        Write-Host "   $ExePath $($ExeArgs -join ' ')"
        if ($JLinkScript) { Write-Host ($scriptLines -join "`n") }
        exit 0
    }
    if (-not $Silent) {
        Write-Host "   $(T 'Flashing')"
    }

    $FlashTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $RetryElapsed = [TimeSpan]::Zero
    if ($DryRun) {
        Write-Warn (T 'DryRunSimulating')
        Start-Sleep -Seconds 2
        $process = [PSCustomObject]@{ ExitCode = 0 }
        if ($SelectedEngine -eq "OPENOCD") {
            $LogContent = "$(T 'DryRunLog')`ntarget voltage: 3.3`n** Programming Finished **`n** Verified OK **`n"
        } elseif (Test-IsJLinkEngine $SelectedEngine) {
            $LogContent = "$(T 'DryRunLog')`nSEGGER J-Link Commander V9.60`nConnecting to J-Link via USB...O.K.`nS/N: 123456789`nVTref=3.300V`nDevice `"$SelectedJLinkDevice`" selected.`nCortex-M4 identified.`nDownloading file [$HexName]...O.K.`n"
        } elseif ($SelectedProbeType -eq "JLINK") {
            $LogContent = "$(T 'DryRunLog')`nSTM32CubeProgrammer v2.21.0`nJ-Link SN  : 123456789`nVoltage     : 3.30V`nFile download complete`nDownload verified successfully`n"
        } else {
            $LogContent = "$(T 'DryRunLog')`nST-LINK SN  : 0671FF555353885087123456`nVoltage     : 3.30V`nFile download complete`nDownload verified successfully`n"
        }
    } else {
        $process = Start-Process -FilePath $ExePath -ArgumentList $ExeArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $LogStd -RedirectStandardError $LogErr
    }
    $FlashTimer.Stop()
    $stdout = Get-Content -LiteralPath $LogStd -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $LogErr -Raw -ErrorAction SilentlyContinue
    if (-not $DryRun) {
        $LogContent = @($stdout, $stderr | Where-Object { $_ }) -join "`n"

        if (
            $SelectedEngine -eq "OPENOCD" -and
            $SelectedProbeSerial -and
            $process.ExitCode -ne 0 -and
            $LogContent -match "No device matches the serial string"
        ) {
            Write-Warn (T "RetryProbeSerial")
            $RetryElapsed = $FlashTimer.Elapsed
            $RetryArgs = @("-s", "`"$OpenOcdScripts`"", "-f", "interface/stlink.cfg", "-c", "`"$(Get-OpenOcdSerialCommand $SelectedProbeSerial bytes)`"", "-f", $TargetCfg, "-c", $TclCmd)
            $FlashTimer.Restart()
            $process = Start-Process -FilePath $ExePath -ArgumentList $RetryArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $LogStd -RedirectStandardError $LogErr
            $FlashTimer.Stop()
            $stdout = Get-Content -LiteralPath $LogStd -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content -LiteralPath $LogErr -Raw -ErrorAction SilentlyContinue
            $LogContent = @($stdout, $stderr | Where-Object { $_ }) -join "`n"
        }

        $savedJLinkSerialWasUsed =
            (-not $Erase) -and
            (-not $Serial) -and
            ($RetryArgsWithoutSerial.Count -gt 0) -and
            (
                ((Test-IsJLinkEngine $SelectedEngine) -and $SelectedJLinkSerial) -or
                ($SelectedProbeType -eq "JLINK" -and $SelectedProbeSerial)
            )
        if (
            $savedJLinkSerialWasUsed -and
            $process.ExitCode -ne 0 -and
            $LogContent -match "(?i)(serial|S/N|No J-Link|Could not find|Cannot connect to J-Link|probe.*not.*found|No probe)"
        ) {
            Write-Warn (T "RetryWithoutSerial")
            $RetryElapsed += $FlashTimer.Elapsed
            $FlashTimer.Restart()
            $process = Start-Process -FilePath $ExePath -ArgumentList $RetryArgsWithoutSerial -NoNewWindow -Wait -PassThru -RedirectStandardOutput $LogStd -RedirectStandardError $LogErr
            $FlashTimer.Stop()
            $stdout = Get-Content -LiteralPath $LogStd -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content -LiteralPath $LogErr -Raw -ErrorAction SilentlyContinue
            $LogContent = @($stdout, $stderr | Where-Object { $_ }) -join "`n"
        }
    }
    $OperationDuration = ($RetryElapsed + $FlashTimer.Elapsed).ToString("hh\:mm\:ss\.fff")
}
$LogContent = Normalize-ToolLog $LogContent

Remove-Item -LiteralPath $LogStd, $LogErr -ErrorAction SilentlyContinue
if ($JLinkScript) { Remove-Item -LiteralPath $JLinkScript -ErrorAction SilentlyContinue }
$LogContent | Set-Content -LiteralPath $LogFile -Encoding UTF8

# ══════════════════════════════════════════════════════════════════════════════
#  5. Парсинг лога (Универсальный)
# ══════════════════════════════════════════════════════════════════════════════

$ExitOk = $process.ExitCode -eq 0
$IsStlinkFound = $false; $IsProgrammed = $false; $IsVerified = $false
$ToolInfo = ""; $StlinkInfo = ""; $TargetVoltage = ""; $McuCore = ""; $McuDevId = ""; $McuDevIdHex = ""; $McuFlash = ""; $McuFamily = ""

$EnginePatterns = @{
    OPENOCD = @{
        Flags = @{
            IsStlinkFound = "(?i)target voltage"
            IsProgrammed  = "\*\* Programming Finished \*\*"
            IsVerified    = "\*\* Verified OK \*\*"
        }
        Fields = [ordered]@{
            ToolInfo      = @{ Pattern = '(?m)^((?:xPack )?Open On-Chip Debugger[^\r\n]+)' }
            StlinkInfo    = @{ Pattern = 'Info\s*:\s*(STLINK[^\r\n]+)' }
            TargetVoltage = @{ Pattern = '(?i)target voltage[^:]*:\s*([\d.]+)'; Suffix = ' V' }
            McuCore       = @{ Pattern = 'Info\s*:\s*(\S+\.cpu[:\s]+Cortex[^\r\n]+)' }
            McuDevIdHex   = @{ Pattern = 'device id(?:code)?\s*=\s*(0x[\da-fA-F]+)' }
            McuFlash      = @{ Pattern = 'flash size\s*=\s*([\d]+\s*KiB)' }
        }
    }
    CUBEPROGRAMMER = @{
        Flags = @{
            IsStlinkFound = "ST-LINK SN|J-Link SN|Voltage"
            IsProgrammed  = "File download complete"
            IsVerified    = "Download verified successfully"
        }
        Fields = [ordered]@{
            ToolInfo      = @{ Pattern = 'STM32CubeProgrammer\s+(v[\d\.]+)'; Prefix = 'STM32CubeProgrammer ' }
            StlinkInfo    = @{ Pattern = '(?m)^\s*(Connecting to J-Link/Flasher Probe|ST-LINK FW\s*:\s*[^\r\n]+|J-Link SN\s*:\s*[^\r\n]+)' }
            TargetVoltage = @{ Pattern = 'Voltage\s*:\s*([^\r\n]+)' }
            McuCore       = @{ Pattern = '(?:Device CPU\s*:|Device=)\s*([^\r\n]+)' }
            McuDevIdHex   = @{ Pattern = 'Device ID\s*:\s*(0x[\da-fA-F]+)' }
            McuFlash      = @{ Pattern = 'Flash size\s*:\s*([^\r\n]+)' }
            McuFamily     = @{ Pattern = 'Device name\s*:\s*([^\r\n]+)' }
        }
    }
    JLINK = @{
        Flags = @{
            IsStlinkFound = "SEGGER J-Link Commander|Connecting to J-Link|S/N:"
            IsProgrammed  = "Downloading file[\s\S]*?O\.K\.|Loading file[\s\S]*?O\.K\."
            IsVerified    = "Downloading file[\s\S]*?O\.K\.|Loading file[\s\S]*?O\.K\."
        }
        Fields = [ordered]@{
            ToolInfo      = @{ Pattern = '(?m)^(SEGGER J-Link Commander[^\r\n]+)' }
            StlinkInfo    = @{ Pattern = '(?m)^\s*(S/N:\s*[^\r\n]+)' }
            TargetVoltage = @{ Pattern = 'VTref\s*=\s*([^\r\n]+)' }
            McuCore       = @{ Pattern = '(Cortex-M[^\r\n]+)' }
            McuFamily     = @{ Pattern = 'Device\s+"?([^"\r\n]+)"?\s+selected' }
        }
    }
}

$ParserKey = if ($SelectedEngine -eq "OPENOCD") { "OPENOCD" } elseif (Test-IsJLinkEngine $SelectedEngine) { "JLINK" } else { "CUBEPROGRAMMER" }
$ParsedLog = Invoke-EngineLogParser $LogContent $EnginePatterns[$ParserKey]
$IsStlinkFound = $ParsedLog.IsStlinkFound
$IsProgrammed  = $ParsedLog.IsProgrammed
$IsVerified    = $ParsedLog.IsVerified
$ToolInfo      = $ParsedLog.ToolInfo
$StlinkInfo    = $ParsedLog.StlinkInfo
$TargetVoltage = $ParsedLog.TargetVoltage
$McuCore       = $ParsedLog.McuCore
$McuDevId      = $ParsedLog.McuDevId
$McuDevIdHex   = $ParsedLog.McuDevIdHex
$McuFlash      = $ParsedLog.McuFlash
$McuFamily     = $ParsedLog.McuFamily
if ((Test-IsJLinkEngine $SelectedEngine) -and -not $McuFamily -and $SelectedJLinkDevice) {
    $McuFamily = $SelectedJLinkDevice
}

if (-not $DryRun -and -not $Serial -and ((Test-IsJLinkEngine $SelectedEngine) -or $SelectedProbeType -eq "JLINK")) {
    $detectedJLinkSerial = ""
    if ($StlinkInfo -match '(?i)S/N\s*:\s*([0-9A-F]+)') {
        $detectedJLinkSerial = $Matches[1]
    } elseif ($StlinkInfo -match '(?i)J-Link SN\s*:\s*([0-9A-F]+)') {
        $detectedJLinkSerial = $Matches[1]
    }
    if ($detectedJLinkSerial) {
        try { Set-Content -LiteralPath (Join-Path $CurrentDir ".jlink_serial") -Value $detectedJLinkSerial -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
}

$IntegrityGateOk = (-not $HashCheckPerformed) -or $HashCheckOk
$Success = $IntegrityGateOk -and $IsStlinkFound -and $IsProgrammed -and $IsVerified -and $ExitOk
if ($Erase) {
    $IsErased = Test-EraseLog $ParserKey $LogContent
    $Success = $ExitOk -and $IsErased
}
if ($Backup) { $Success = $ExitOk -and $BackupSaved }

if ($Success) {
    Write-Ok (T "OkSuccess")
    Write-Info "$(T 'ConsoleDuration'): $OperationDuration"
} else {
    Write-Err "$(T 'ErrFailed')$($process.ExitCode)"
    Write-Info "$(T 'ConsoleDuration'): $OperationDuration"
    Write-Info (T "OpeningReport")
}

# ══════════════════════════════════════════════════════════════════════════════
#  6. HTML-отчёт
# ══════════════════════════════════════════════════════════════════════════════

$NowLocal   = [DateTimeOffset]::Now
$NowUtc     = $NowLocal.ToUniversalTime()
$Timestamp  = "$(T 'ReportTimeLocal'): $($NowLocal.ToString('yyyy-MM-dd HH:mm:ss zzz')) | $(T 'ReportTimeUtc'): $($NowUtc.ToString('yyyy-MM-dd HH:mm:ss ''UTC'''))"
$ResultBg   = if ($Success) { "#d1f0de" } else { "#fde8e8" }
$ResultFg   = if ($Success) { "#0f5c2e" } else { "#7a1c1c" }
$ResultIcon = if ($Success) { "&#10003;" } else { "&#10007;" }
$ResultMsg  = if ($Success) { T "SuccessMsg" } else { T "ErrorMsg" }

$BadgeBg    = switch ($BuildType) { "Release" { "#0d6efd" } "Debug" { "#fd7e14" } default { "#6c757d" } }
$HexNameEsc = Escape-Html $HexName

# Переводы для таблицы Build Info в зависимости от языка
$LabelMap = [ordered]@{
    "Firmware Version" = if ($ActiveLang -eq $LangRu) { "Версия прошивки" } else { "Firmware Version" }
    "Stamp"            = if ($ActiveLang -eq $LangRu) { "Метка сборки" } else { "Build Stamp" }
    "Integrity"        = if ($ActiveLang -eq $LangRu) { "Целостность (CRC32)" } else { "Integrity (CRC32)" }
    "Project"          = if ($ActiveLang -eq $LangRu) { "Проект" } else { "Project" }
    "System"           = if ($ActiveLang -eq $LangRu) { "HAL / SDK" } else { "HAL / SDK" }
    "Compiler"         = if ($ActiveLang -eq $LangRu) { "Компилятор" } else { "Compiler" }
    "Build Type"       = if ($ActiveLang -eq $LangRu) { "Тип сборки" } else { "Build Type" }
    "Branch"           = if ($ActiveLang -eq $LangRu) { "Ветка Git" } else { "Git Branch" }
    "Author"           = if ($ActiveLang -eq $LangRu) { "Автор" } else { "Author" }
    "Commit Message"   = if ($ActiveLang -eq $LangRu) { "Коммит" } else { "Commit" }
    "Commit Link"      = if ($ActiveLang -eq $LangRu) { "Ссылка на коммит" } else { "Commit Link" }
    "Releases Page"    = if ($ActiveLang -eq $LangRu) { "Страница релизов" } else { "Releases Page" }
}
$BiRows = ""
foreach ($key in $BuildInfo.Keys) {
    $label = if ($LabelMap[$key]) { $LabelMap[$key] } else { Escape-Html $key }
    $val = $BuildInfo[$key] -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2" target="_blank">$1</a>' -replace '(?<!href=")(https?://[^\s<>"]+)', '<a href="$1" target="_blank">$1</a>'
    $BiRows += "<tr><th>$label</th><td>$val</td></tr>`n"
}
$BuildInfoSection = if ($BiRows) { "<div class='card'><h2>&#128196; $(T 'Build') ($BuildType)</h2><table>$BiRows</table></div>" } else { "" }

$ChangelogSection = ""
if ($ChangelogContent) {
    $ChangelogHtml = Md-ToHtml $ChangelogContent
    $ChangelogPathUrl = "file:///$($ChangelogPath -replace '\\','/')"
    $ChangelogSection = "<div class='card'><h2>&#128221; $(T 'Changelog')</h2><div class='changelog-box'>$ChangelogHtml</div><p class='changelog-footer'>$(T 'Source'): <a href='$ChangelogPathUrl' target='_blank'>CHANGELOG.md</a></p></div>"
}

$IntegrityRow = if ($HashCheckPerformed) {
    if ($HashCheckOk) {
        "<tr><th>$(T 'IntegrityCheck')</th><td><span class='ok'>&#10003; $(T 'IntegrityPassed')</span></td></tr>"
    } else {
        "<tr><th>$(T 'IntegrityCheck')</th><td><span class='err'>&#10007; $(T 'IntegrityFailed')</span></td></tr>"
    }
} else {
    "<tr><th>$(T 'IntegrityCheck')</th><td><span class='warn'>$(T 'IntegrityNotChecked')</span></td></tr>"
}

$IntegritySection = ""
if ($HashCheckPerformed -or $HashSpecPath -or $Sha256) {
    $IntegritySourceValue = if ($HashSource) { Escape-Html $HashSource } else { "<em class='na'>—</em>" }
    $IntegrityExpectedValue = if ($HashExpected) { "<code>$(Escape-Html $HashExpected)</code>" } else { "<em class='na'>—</em>" }
    $IntegrityActualValue = if ($HashActual) { "<code>$(Escape-Html $HashActual)</code>" } else { "<em class='na'>—</em>" }
    $IntegritySection = @"
  <div class="card">
    <h2>&#128274; $(T 'IntegrityCheck')</h2>
    <table>
      <tr><th>$(T 'IntegritySource')</th><td>$IntegritySourceValue</td></tr>
      <tr><th>$(T 'IntegrityExpected')</th><td>$IntegrityExpectedValue</td></tr>
      <tr><th>$(T 'IntegrityActual')</th><td>$IntegrityActualValue</td></tr>
    </table>
  </div>
"@
}

$EnvTool   = if ($ToolInfo)       { Escape-Html $ToolInfo }        else { "<em class='na'>$(T 'ToolNotDetected')</em>" }
$EnvStlink = if ($StlinkInfo)     { Escape-Html $StlinkInfo }      else { "<em class='na'>$(T 'StLinkNotFound')</em>" }
$EnvVolt   = if ($TargetVoltage)  { "<strong>$(Escape-Html $TargetVoltage)</strong>" } else { "<em class='na'>—</em>" }
$EnvCore   = if ($McuCore)        { Escape-Html $McuCore }         else { "<em class='na'>—</em>" }
$EnvFamily = if ($McuFamily)      { "<strong>$(Escape-Html $McuFamily)</strong>" }    else { "<em class='na'>—</em>" }
$EnvDevId  = if ($McuDevId)       { "<code>$(Escape-Html $McuDevId)</code>" }         else { "<em class='na'>—</em>" }
$EnvFlash  = if ($McuFlash)       { Escape-Html $McuFlash }        else { "<em class='na'>—</em>" }
$EnvOperator = if ($OperatorName) { Escape-Html $OperatorName } else { "<em class='na'>—</em>" }
$EnvUserAccount = if ($UserAccount) { Escape-Html $UserAccount } else { "<em class='na'>—</em>" }
$EnvMachine = if ($MachineName) { Escape-Html $MachineName } else { "<em class='na'>—</em>" }
$EnvNetworkHost = if ($NetworkHostName) { Escape-Html $NetworkHostName } else { "<em class='na'>—</em>" }
$EnvWin    = Escape-Html $WinInfo
$EnvPs     = Escape-Html $PsVerStr
$EnvScriptVersion = Escape-Html $VERSION

$LogHtml = Escape-Html $LogContent
$ProjectTitle = if ($BuildInfo["Project"]) { Escape-Html $BuildInfo["Project"] } else { Escape-Html ($HexName -replace '\.hex$','') }
$HistoryIndexRelative = ".history/index.html"
$HistoryIndexLink = "<a href='$HistoryIndexRelative'>$(T 'HistoryTitle')</a>"
if ($Erase) { $ProjectTitle = T 'EraseName'; $HexNameEsc = ''; $IntegrityRow = '' }
if ($Backup) { $ProjectTitle = T 'BackupName'; $HexNameEsc = Escape-Html ([IO.Path]::GetFileName($BackupOutput)); $IntegrityRow = '' }
$OperationRows = if ($Erase) {
    Status-Row (T 'EraseName') $IsErased (T 'Yes') (T 'No')
} elseif ($Backup) {
    (Status-Row (T 'BackupName') $BackupSaved (T 'Yes') (T 'No')) +
    "<tr><th>$(T 'BackupRange')</th><td>$(Escape-Html $BackupRangeLabel)</td></tr><tr><th>HEX</th><td>$(Escape-Html $BackupOutput)</td></tr>"
} else {
    (Status-Row (T 'FlashWrite') $IsProgrammed (T 'WriteCompleted') (T 'WriteError')) +
    (Status-Row (T 'Verification') $IsVerified (T 'VerPassed') (T 'VerFailed'))
}

$HtmlContent = @"
<!DOCTYPE html>
<html lang="$( if ($ActiveLang -eq $LangRu) { 'ru' } else { 'en' } )">
<head>
  <meta charset="UTF-8">
  <title>$(T 'HtmlTitle') — $ProjectTitle</title>
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
    tr:nth-child(even) th, tr:nth-child(even) td { background: #fcfcfd; }
    tr:last-child th, tr:last-child td { border-bottom: none; }
    .sh th { color: #6c757d; font-size: .75rem; letter-spacing: .06em; text-transform: uppercase; }
    .sh-host th { background: #e7f1ff !important; color: #355070; }
    .sh-programmer th { background: #eafaf1 !important; color: #2d6a4f; }
    .sh-mcu th { background: #fff4e6 !important; color: #9c6644; }
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
    <h1>&#128268; $(T 'HtmlTitle') — $ProjectTitle</h1>
    <span class="badge">$HexNameEsc</span>
  </div>
  <p class="sub">$Timestamp</p>
  <div class="result-banner"><span class="ico">$ResultIcon</span><span>$ResultMsg</span></div>
  <div class="grid2">
    <div class="card">
      <h2>&#9745; $(T 'StatusStages')</h2>
      <table>
        $IntegrityRow
        $(Status-Row (T 'StLinkDetected')  $IsStlinkFound (T 'Yes')           (T 'No'))
        $OperationRows
        <tr><th>$(T 'OperationDuration')</th><td><code>$OperationDuration</code></td></tr>
        $(Status-Row (T 'ExitCode')        $ExitOk        (T 'ExitSuccess')    "$($process.ExitCode) $(T 'ExitError')")
      </table>
    </div>
$BuildInfoSection
  </div>
  <div class="card">
    <h2>&#128187; $(T 'Scheme')</h2>
    <table>
      <tr class="sh sh-host"><th colspan="2">$(T 'Host')</th></tr>
      <tr><th>$(T 'Operator')</th><td>$EnvOperator</td></tr>
      <tr><th>$(T 'UserAccount')</th><td>$EnvUserAccount</td></tr>
      <tr><th>$(T 'Machine')</th><td>$EnvMachine</td></tr>
      <tr><th>$(T 'NetworkHost')</th><td>$EnvNetworkHost</td></tr>
      <tr><th>$(T 'ScriptVersion')</th><td><code>$EnvScriptVersion</code></td></tr>
      <tr><th>$(T 'HistoryTitle')</th><td>$HistoryIndexLink</td></tr>
      <tr><th>$(T 'OS')</th><td>$EnvWin</td></tr>
      <tr><th>$(T 'PowerShell')</th><td>$EnvPs</td></tr>
      <tr><th>$(T 'FlashEngine')</th><td>$EnvTool</td></tr>
      <tr class="sh sh-programmer"><th colspan="2">$(T 'Programmer')</th></tr>
      <tr><th>$(T 'StLink')</th><td>$EnvStlink</td></tr>
      <tr><th>$(T 'TargetVoltage')</th><td>$EnvVolt</td></tr>
      <tr class="sh sh-mcu"><th colspan="2">$(T 'Mcu')</th></tr>
      <tr><th>$(T 'Family')</th><td>$EnvFamily</td></tr>
      <tr><th>$(T 'Core')</th><td>$EnvCore</td></tr>
      <tr><th>$(T 'DeviceId')</th><td>$EnvDevId</td></tr>
      <tr><th>$(T 'Flash')</th><td>$EnvFlash</td></tr>
    </table>
  </div>
$ChangelogSection
$IntegritySection
  <div class="card">
    <h2>&#128220; $(T 'ToolOutput')</h2>
    <pre>$LogHtml</pre>
  </div>
</body>
</html>
"@

Set-Content -LiteralPath $HtmlReport -Value $HtmlContent -Encoding UTF8
$HistoryEntry = [ordered]@{
    TimestampTag = $NowLocal.ToString('yyyyMMdd_HHmmss')
    TimestampLocal = $NowLocal.ToString('yyyy-MM-dd HH:mm:ss zzz')
    TimestampUtc = $NowUtc.ToString('o')
    Success = $Success
    Operation = if ($Erase) { 'erase' } elseif ($Backup) { 'backup' } else { 'flash' }
    BackupFile = $BackupOutput
    BackupRange = $BackupRangeLabel
    ResultText = if ($Success) { T 'SuccessMsg' } else { T 'ErrorMsg' }
    HexName = if ($Backup -and $BackupSaved) { [IO.Path]::GetFileName($BackupOutput) } else { $HexName }
    EngineName = Get-EngineDisplayName $SelectedEngine
    OperationDuration = $OperationDuration
    ReportFile = ""
    LogFile = ""
}
Save-HistoryArtifacts $HistoryDir $LogFile $HtmlReport $HistoryEntry
if (-not $Success) {
    try { Invoke-Item $HtmlReport } catch { Write-Warn $_.Exception.Message }
    exit 1
}
exit 0
