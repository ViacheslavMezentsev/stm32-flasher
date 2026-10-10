# stm32-flasher

[English version below](#english)

---

## Русский

Утилита для прошивки STM32 через ST-Link или J-Link. Один файл, минимум подготовки, отчёт по результату.

**Поддерживаемые движки:** OpenOCD (установленный или скачивается автоматически), STM32CubeProgrammer (если установлен), SEGGER J-Link Commander (если установлен).
Поддерживается выбор конкретного ST-Link или J-Link, если к ПК подключено несколько программаторов.
Поддерживается предварительная проверка SHA-256 для `*.hex` перед прошивкой.
Поддерживается локальная история последних сессий прошивки в `.history\`.
Рабочие операции в одной папке защищены от одновременного запуска. Справка, DryRun и обычный info остаются доступны; подробные границы — в [инструкции](docs/user-guide.md).

Версия **0.2.12**. Необязательные команды-обёртки держите рядом с `flash.cmd`:

Все команды поддерживают `--help` (`-Help`, `-h`) и `--version` (`-Version`): только справка или версия, без выполнения операций. Язык: `-Lang ru` / `-Lang en`.

`-DryRun` показывает план без запуска утилит, опроса USB/MCU, сети и изменения файлов. Проверяет локальный Intel HEX и SHA-256 при наличии; не проверяет совместимость с платой. Код `0` означает готовность плана, `1` — ошибку или нехватку параметров.

| Команда | Действие |
|---|---|
| `erase.cmd` | Полное стирание Flash |
| `backup.cmd` | Резервная копия в Intel HEX + SHA-256 в `backups` |
| `info.cmd` | Обзор ПК, инструментов, USB-программаторов и сохранённых настроек |
| `setup.cmd` | Перенастройка движка и программатора с подтверждением, без операций с MCU |
| `verify.cmd` | Сравнение диапазонов HEX с памятью MCU без записи и стирания |
| `forget.cmd` | Удаление настроек, логов, отчётов и скачанных инструментов; копии сохраняются |

Несколько программаторов при backup/erase выбираются через меню. `info.cmd -ProbeTarget` подключается к выбранному MCU. `forget.cmd -DryRun` показывает список удаления; `flash.cmd -ResetConfig` сбрасывает только настройки.

`verify.cmd` может остановить ядро; автоматически не сбрасывает и не запускает его.
Используйте полное имя `verify.cmd`: `verify` в CMD является другой встроенной командой.

### Быстрый старт

1. Скопируйте `flash.cmd` из `bin` репозитория (или корня релизного ZIP) рядом с `*.hex`; нужные обёртки скопируйте туда же
2. Подключите ST-Link или J-Link к компьютеру и плате
3. Двойной клик по `flash.cmd`
4. Если `*.hex` один, прошивка начнётся сразу

`bin` нужен только для хранения исходников. При запуске команд по полному пути настройки, HEX, отчёты и история по-прежнему относятся к папке вызова.

### Требования

- Windows 10 / 11
- PowerShell 5.1 (встроен) или 7+ (рекомендуется: `winget install Microsoft.PowerShell`)
- Драйверы ST-Link — [st.com/stlink-v2](https://www.st.com/en/development-tools/stsw-link009.html) или SEGGER J-Link Software — [segger.com/downloads/jlink](https://www.segger.com/downloads/jlink/)
- Интернет при первом запуске:
  - загрузка OpenOCD ~5 MB, если CubeProgrammer не установлен;
  - загрузка `stlink` tools, если нужен `st-info` и он не найден локально.

Подробная инструкция: [Инструкция по использованию](docs/user-guide.md). Проверки и структура рабочих каталогов: [тестирование](docs/testing.md).

### Файлы, создаваемые автоматически

| Файл | Назначение |
|---|---|
| `.tools\` | OpenOCD (скачивается один раз) |
| `.flash.json` | Движок, тип/serial программатора, device/target; [формат и миграция](docs/reference/launch-configuration.md) |
| `*.hex.sha256` / `*.sha256` | Опциональная контрольная сумма SHA-256 для `*.hex` |
| `flash_log.txt` | Лог последней прошивки |
| `report.html` | HTML-отчёт последней прошивки |
| `.history\` | Архив отчётов и логов предыдущих сессий |
| `backups\` | Резервные копии Flash; `forget.cmd` их не удаляет |

---

## English <a name="english"></a>

Working operations in one directory are protected against concurrent runs. Help, DryRun and basic info remain available; scope and limitations are documented in [HOWTO](docs/en/HOWTO.md#concurrent-runs).

Version **0.2.12**. Keep optional command wrappers next to `flash.cmd`:

| Command | Action |
|---|---|
| `setup.cmd` | Reconfigure engine and probe with confirmation, without MCU operations |
| `erase.cmd` | Full Flash erase |
| `backup.cmd` | Intel HEX + SHA-256 backup in `backups` |
| `info.cmd` | PC, tools, USB probes and saved settings overview |
| `forget.cmd` | Remove settings, logs, reports and downloaded tools; preserve backups |
| `verify.cmd` | Compare HEX ranges with MCU memory without programming or erasing |

Backup/erase prompt when multiple probes are connected. `info.cmd -ProbeTarget` connects to the selected MCU. `forget.cmd -DryRun` previews cleanup; `flash.cmd -ResetConfig` resets settings only.

`verify.cmd` may halt the core; it does not automatically reset or resume it.
Use the full name `verify.cmd`: bare `verify` is a different built-in CMD command.

All commands accept `--help` (`-Help`, `-h`) and `--version` (`-Version`): information only, without executing operations. Language: `-Lang ru` / `-Lang en`.

`-DryRun` previews the plan without running tools, querying USB/MCU, network access or file changes. It validates local Intel HEX and SHA-256 when provided, not board compatibility. Exit `0` means the plan is complete; `1` means an error or missing parameters.

STM32 flashing utility via ST-Link or J-Link. Single file, minimal setup, result report included.

**Supported engines:** OpenOCD (installed or auto-downloaded), STM32CubeProgrammer (if installed), SEGGER J-Link Commander (if installed).
Supports selecting a specific ST-Link or J-Link when multiple programmers are connected.
Supports optional SHA-256 verification for `*.hex` before flashing.
Supports a local flash-session history in `.history\`.

### Quick start

1. Copy `flash.cmd` from the repository's `bin` (or release ZIP root) next to your `*.hex`; copy any needed wrappers beside it
2. Connect ST-Link or J-Link to PC and board
3. Double-click `flash.cmd`
4. If there is only one `*.hex`, flashing starts immediately

`bin` is only a source layout. When invoking commands by full path, settings, HEX files, reports and history still belong to the working directory.

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
| `.flash.json` | Engine, probe type/serial, device/target; [format and migration](docs/reference/launch-configuration.md#english) |
| `*.hex.sha256` / `*.sha256` | Optional SHA-256 checksum for `*.hex` |
| `flash_log.txt` | Last flash log |
| `report.html` | Last flash HTML report |
| `.history\` | Archive of reports and logs from previous sessions |
| `backups\` | Flash backups; preserved by `forget.cmd` |
