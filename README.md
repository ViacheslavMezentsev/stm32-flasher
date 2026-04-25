# stm32-flasher

[English version below](#english)

---

## Русский

Утилита для прошивки STM32 через ST-Link. Один файл, минимум подготовки, отчёт по результату.

**Поддерживаемые движки:** OpenOCD (встроенный, скачивается автоматически), STM32CubeProgrammer (если установлен).

### Быстрый старт

1. Положите `flash.cmd` рядом с файлом `*.hex`
2. Подключите ST-Link к компьютеру и плате
3. Двойной клик по `flash.cmd`
4. Если `*.hex` один, прошивка начнётся сразу

### Требования

- Windows 10 / 11
- PowerShell 5.1 (встроен) или 7+ (рекомендуется: `winget install Microsoft.PowerShell`)
- Драйверы ST-Link — [st.com/stlink-v2](https://www.st.com/en/development-tools/stsw-link009.html)
- Интернет при первом запуске (загрузка OpenOCD ~5 MB, если CubeProgrammer не установлен)

Подробная инструкция: [Инструкция по использованию](<D:/github/ViacheslavMezentsev/stm32-flasher/Инструкция по использованию stm32-flasher.md>)

### Файлы, создаваемые автоматически

| Файл | Назначение |
|---|---|
| `.tools\` | OpenOCD (скачивается один раз) |
| `.flash_engine` | Сохранённый выбор движка |
| `.openocd_target` | Сохранённый таргет-конфиг OpenOCD |
| `flash_log.txt` | Лог последней прошивки |
| `report.html` | HTML-отчёт последней прошивки |

---

## English <a name="english"></a>

STM32 flashing utility via ST-Link. Single file, minimal setup, result report included.

**Supported engines:** OpenOCD (built-in, auto-downloaded), STM32CubeProgrammer (if installed).

### Quick start

1. Place `flash.cmd` next to your `*.hex` file
2. Connect ST-Link to PC and board
3. Double-click `flash.cmd`
4. If there is only one `*.hex`, flashing starts immediately

### Requirements

- Windows 10 / 11
- PowerShell 5.1 (built-in) or 7+ (recommended: `winget install Microsoft.PowerShell`)
- ST-Link drivers — [st.com/stlink-v2](https://www.st.com/en/development-tools/stsw-link009.html)
- Internet on first run (OpenOCD ~5 MB download, if CubeProgrammer is not installed)

### Auto-created files

| File | Purpose |
|---|---|
| `.tools\` | OpenOCD (downloaded once) |
| `.flash_engine` | Saved engine choice |
| `.openocd_target` | Saved OpenOCD target config |
| `flash_log.txt` | Last flash log |
| `report.html` | Last flash HTML report |
