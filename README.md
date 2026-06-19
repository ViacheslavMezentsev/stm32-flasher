# stm32-flasher

[English version below](#english)

---

## Русский

Утилита для прошивки STM32 через ST-Link или J-Link. Один файл, минимум подготовки, отчёт по результату.

**Поддерживаемые движки:** OpenOCD (встроенный, скачивается автоматически), STM32CubeProgrammer (если установлен), SEGGER J-Link Commander (если установлен).
Поддерживается выбор конкретного ST-Link или J-Link, если к ПК подключено несколько программаторов.
Поддерживается предварительная проверка SHA-256 для `*.hex` перед прошивкой.
Поддерживается локальная история последних сессий прошивки в `.history\`.

### Быстрый старт

1. Положите `flash.cmd` рядом с файлом `*.hex`
2. Подключите ST-Link или J-Link к компьютеру и плате
3. Двойной клик по `flash.cmd`
4. Если `*.hex` один, прошивка начнётся сразу

### Требования

- Windows 10 / 11
- PowerShell 5.1 (встроен) или 7+ (рекомендуется: `winget install Microsoft.PowerShell`)
- Драйверы ST-Link — [st.com/stlink-v2](https://www.st.com/en/development-tools/stsw-link009.html) или SEGGER J-Link Software — [segger.com/downloads/jlink](https://www.segger.com/downloads/jlink/)
- Интернет при первом запуске:
  - загрузка OpenOCD ~5 MB, если CubeProgrammer не установлен;
  - загрузка `stlink` tools, если нужен `st-info` и он не найден локально.

Подробная инструкция: [Инструкция по использованию](<D:/github/ViacheslavMezentsev/stm32-flasher/Инструкция по использованию stm32-flasher.md>)

### Файлы, создаваемые автоматически

| Файл | Назначение |
|---|---|
| `.tools\` | OpenOCD (скачивается один раз) |
| `.flash_engine` | Сохранённый выбор движка |
| `.openocd_target` | Сохранённый таргет-конфиг OpenOCD |
| `.probe_type` | Сохранённый тип отладчика (`STLINK` / `JLINK`) |
| `.stlink_serial` | Сохранённый выбор конкретного ST-Link |
| `.jlink_device` | Сохранённое имя устройства J-Link, например `STM32G431CB` |
| `.jlink_serial` | Сохранённый serial J-Link, если он был явно указан или найден в логе |
| `*.hex.sha256` / `*.sha256` | Опциональная контрольная сумма SHA-256 для `*.hex` |
| `flash_log.txt` | Лог последней прошивки |
| `report.html` | HTML-отчёт последней прошивки |
| `.history\` | Архив отчётов и логов предыдущих сессий |

---

## English <a name="english"></a>

STM32 flashing utility via ST-Link or J-Link. Single file, minimal setup, result report included.

**Supported engines:** OpenOCD (built-in, auto-downloaded), STM32CubeProgrammer (if installed), SEGGER J-Link Commander (if installed).
Supports selecting a specific ST-Link or J-Link when multiple programmers are connected.
Supports optional SHA-256 verification for `*.hex` before flashing.
Supports a local flash-session history in `.history\`.

### Quick start

1. Place `flash.cmd` next to your `*.hex` file
2. Connect ST-Link or J-Link to PC and board
3. Double-click `flash.cmd`
4. If there is only one `*.hex`, flashing starts immediately

### Requirements

- Windows 10 / 11
- PowerShell 5.1 (built-in) or 7+ (recommended: `winget install Microsoft.PowerShell`)
- ST-Link drivers — [st.com/stlink-v2](https://www.st.com/en/development-tools/stsw-link009.html) or SEGGER J-Link Software — [segger.com/downloads/jlink](https://www.segger.com/downloads/jlink/)
- Internet on first run:
  - OpenOCD ~5 MB download, if CubeProgrammer is not installed;
  - `stlink` tools download, if `st-info` is needed and not found locally.

### Auto-created files

| File | Purpose |
|---|---|
| `.tools\` | OpenOCD (downloaded once) |
| `.flash_engine` | Saved engine choice |
| `.openocd_target` | Saved OpenOCD target config |
| `.probe_type` | Saved probe type (`STLINK` / `JLINK`) |
| `.stlink_serial` | Saved ST-Link selection |
| `.jlink_device` | Saved J-Link device name, for example `STM32G431CB` |
| `.jlink_serial` | Saved J-Link serial, if explicitly provided or detected in the log |
| `*.hex.sha256` / `*.sha256` | Optional SHA-256 checksum for `*.hex` |
| `flash_log.txt` | Last flash log |
| `report.html` | Last flash HTML report |
| `.history\` | Archive of reports and logs from previous sessions |
