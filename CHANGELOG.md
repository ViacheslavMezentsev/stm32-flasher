# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project uses semantic versioning in `Major.Minor.Patch` form while it is still in active development.

## [Unreleased]

### Аппаратные проверки
- Владелец подтвердил на STM32G474RE/ST-Link обычную прошивку через CubeProgrammer (3.514 с) и последующий check (1.089 с): данные диапазонов HEX совпадают с памятью MCU. Основание — консольный вывод, не повторный опыт агента; вся Flash, состояние ядра после check и ошибочный аппаратный сценарий не проверены. Check через OpenOCD и новые команды через J-Link остаются непроверенными на оборудовании.
- Исправление анализа частоты OpenOCD слито в main (ea7e045); CI рабочей ветки и main успешен.

### Добавлено

- `halt.cmd`, `go.cmd`, `reset.cmd`: тонкие обёртки `flash.cmd -Command`, общие настройки, выбор программатора, блокировка папки, отчёт и история. HEX не нужен; запись/стирание Flash и очистка настроек не выполняются.
- Управление через OpenOCD/ST-Link и SEGGER/J-Link; CubeProgrammer/ST-Link — halt/reset с HOTPLUG, без неявного сброса при подключении. CubeProgrammer go и управление через его J-Link отклоняются до обращения к MCU; автоматической смены движка нет.
- Успех требует кода 0 и ожидаемого состояния ядра; ошибки/неизвестный ответ дают 1, без повтора на другом serial. Test-CoreControl использует настоящий CMD и EXE-заглушки; аппаратная проверка ещё не выполнена.
- После добавления управления ядром все 21 набор прошли локально в PS5.1/7, включая 120 новых сценариев, справку, блокировку, локализацию и упаковку. CI рабочей ветки ожидается после push.
- Новая команда сравнения называется `check`, чтобы не пересекаться со встроенным `verify` в CMD. Экспериментальный ключ `-Command verify` больше не принимается; прежняя история не изменяется.
- `check.cmd` / `flash.cmd -Command check`: чтение диапазонов Intel HEX и побайтное сравнение на ПК через CubeProgrammer, OpenOCD или J-Link. Без команд записи, стирания, сброса и автоматического запуска; ядро может остаться остановленным. Пробелы между диапазонами не читаются. Отдельный результат check в отчёте и истории.
- Проверки HEX, перекрытий, границ адресов и SHA-256 до обращения к MCU; ошибки чтения и несовпадения возвращают 1. Тесты CMD с EXE-заглушками, справка RU/EN, DryRun и упаковка новой обёртки. Объём аппаратной проверки check указан выше.
- Прежние 19 наборов прошли в PS5.1/7; новый Test-Verify после исправлений тестового сценария прошёл отдельно (72 случая на каждую версию). CI после push ещё предстоит.

### Изменено
- Настройки объединены в `.flash.json` с версией схемы 1. Старые файлы переносятся при рабочем запуске или сохранении setup; JSON имеет приоритет. Запись через временный файл и атомарную замену, удаление старых настроек после проверки JSON.
- Info/DryRun не мигрируют файлы, help/version не читают настройки. Неверный JSON отклоняется до обнаружения оборудования; явный ResetConfig/forget очищает оба формата. Добавлены тесты миграции, ошибок записи/удаления, RU/EN и приоритета параметров; описание включено в релизный ZIP.
- После перехода на JSON все 19 наборов прошли локально в PS5.1/7 без MCU; ТЗ strict без замечаний. Результат CI этого этапа пока не подтверждён.
- Владелец подтвердил миграцию в JSON и успешную прошивку с проверкой через CubeProgrammer/ST-Link (3.406 с) по консольному выводу и созданному файлу настроек. Последующий info подтвердил чтение JSON и сохранённый выбор движка и программатора.
- CMD перенесены в `bin` репозитория. Релизный ZIP сохраняет команды в корне для копирования к прошивке; рабочие данные остаются в папке вызова.
- CI и упаковка используют новые пути. Test-FlashEntry проверяет оба размещения CMD с EXE-заглушками; Test-PackageLayout выполняет блок упаковки release workflow, проверяет SHA-256, неизменность CMD и переносимый запуск справки RU/EN.
- Локально прошли все 18 наборов в PS5.1/7 и ТЗ strict. Аппаратные операции не выполнялись; CI GitHub ожидается после push.

### Исправлено
- Убрано ложное отклонение успешного управления OpenOCD при штатном снижении частоты адаптера. Исключается только точная информационная строка; настоящие ошибки, отсутствие состояния и ненулевой код по-прежнему означают отказ. На STM32G474RE/ST-Link проверены OpenOCD halt/go/reset и CubeProgrammer halt/reset без записи Flash; состояние после отключения не гарантируется.
- Путь к HEX при передаче CubeProgrammer заключён в кавычки, включая резервные аргументы: папка с пробелами больше не разбивает путь на части. Дефект выявлен новым CMD-тестом до исправления.

## [0.2.12] - 2026-10-10

### Исправлено
- Владелец подтвердил исправленный запуск без аргументов с единственным HEX: запись и проверка через CubeProgrammer/ST-Link успешны (3.584 с).
- Исправлен молчаливый выход `flash.cmd` без аргументов (issue #1). В 0.2.10–0.2.11 CMD-подстановка кавычек для пустой FLASH_ARGS портила команду запуска PowerShell; 0.2.9 не затронута. Экранирование теперь выполняется только для непустых аргументов.
- Добавлен Test-FlashEntry: запуск через CMD с EXE-заглушками CubeProgrammer, OpenOCD и J-Link. Проверяются один HEX без аргументов, свежая/сохранённая конфигурация, явные пути, отсутствие HEX, неверный выбор нескольких HEX, ошибки утилит, отсутствие маркера проверки и несовпадение SHA-256. Отчёты и история проверяются после настоящего дочернего процесса; MCU не используется.

### Документация
- В TODO зафиксирован выпуск 0.2.11, успешный CI всех 16 наборов в PS5.1/7 и Release. Независимая проверка скачанного ZIP остаётся открытой из-за сетевой ошибки среды. Предложена проверка CI коммита тега перед сборкой assets; поведение workflow пока не менялось.

## [0.2.11] - 2026-10-09

### Проверки выпуска
- Все 15 наборов прошли в PowerShell 5.1/7; ТЗ strict без замечаний. Проверены 15 файлов локального ZIP, SHA-256 и справка/версия всех шести команд на RU/EN.
- По ручным логам подтверждены смена CubeProgrammer/ST-Link на J-Link, отмена перед сохранением, отказ второго setup, доступность справки/info при блокировке и повторный запуск после освобождения. Запись и стирание MCU не выполнялись.
- Добавлен Test-Localization: ключи RU/EN, непустые переводы, индексы подстановок и буквальные вызовы T; расширена проверка справки всех команд на оба языка. Наборы автоматически включаются в CI PS5.1/7; качество перевода остаётся ручной проверкой.

### Параллельные запуски
- Flash/erase/backup/setup/forget/ResetConfig и info с ProbeTarget захватывают общую блокировку папки до оборудования и записи. Второй запуск сразу получает локализованное сообщение и код 1. Help/version, DryRun и базовый info не блокируются.
- Именованный mutex освобождается при выходе процесса, без lock-файлов. Защита ограничена одним ПК и нормализованным путём; не объединяет junction/SUBST/сетевые псевдонимы, не защищает один программатор из разных папок и не восстанавливает прерванную операцию.
- Добавлен TC-37 с двумя процессами и аварийным завершением владельца, без MCU.

### Настройка
- Добавлен мастер `setup.cmd` (`flash.cmd -Setup`): выбор движка и программатора, необязательные target/device, подтверждение или отмена. Авто для программатора задаётся по типу; старые несовместимые настройки удаляются только при сохранении. HEX, логи, история и инструменты сохраняются.
- Help/version и DryRun завершаются без обнаружения оборудования и записи; мастер не подключается к MCU и не скачивает утилиты. Добавлены проверки без MCU и упаковка новой обёртки.
- Сохранённый тип программатора учитывается при автоматическом выборе движка. При сохранённом типе без serial несколько устройств требуют меню вместо выбора первого J-Link.

### Документация
- В TODO отмечен выпуск 0.2.10, результаты CI/Release и оставшаяся проверка скачанного архива; предложен следующий этап защиты от параллельных операций, без изменения кода.

## [0.2.10] - 2026-10-09

### Описания релизов
- Добавлены `docs/releases/v<версия>.md`: краткое описание на русском и свёрнутый английский перевод со ссылками на CHANGELOG. Владелец вручную публикует релиз с этим текстом; workflow запускается по `release: published`, проверяет версию и прикладывает ZIP/SHA-256 без изменения заголовка и описания. Push тега больше не публикует релиз.

### Аппаратная приёмка
- Перед 0.2.10 проверены backup/erase/restore на WeAct BluePill-Plus с 128 КиБ: CubeProgrammer 2.19.0 со ST-Link и J-Link, OpenOCD 0.12.0 со ST-Link, SEGGER Commander V8.32 с J-Link V9.60. Повторное чтение подтвердило полное стирание и побайтное восстановление. Для CubeProgrammer/J-Link запуск потребовал отдельного reset, как предусмотрено ограничением этого режима.
- Проверены выбор J-Link в смешанном меню info и очистка отдельного стенда с сохранением прошивки и backups. Рабочий код в рамках аппаратной приёмки не менялся.

### Отчёты и история
- Последовательные сессии в одну секунду больше не перезаписывают архив: при занятом имени добавляется `_1`, `_2` и далее, включая неполные старые наборы. В новых архивных отчётах исправлена ссылка на индекс истории. Старые отчёты не переписываются; параллельные запуски не защищены этим изменением.
- Добавлена регрессия накопления истории: сохранность сессий, ссылки, сортировка и последние 20 строк индекса без удаления старых архивов, PS5.1/7.
- Добавлен TC-20: процессные проверки flash/erase/backup с имитацией CubeProgrammer, RU/EN, успехом и ошибкой; для flash/erase также нулевой код без признаков успеха. Проверяются HTML, JSON, архивные файлы, ссылки индекса, время, длительность и политика открытия браузера. Рабочий код не изменён; набор автоматически включён в CI PS5.1/7.

### Прогресс CI
- Runner передаёт строки stdout/stderr в консоль по мере поступления и одновременно сохраняет UTF-8 логи. Для каждого набора выводятся PASS/FAIL, время и код; `results.json` дополнен `DurationSeconds`.
- Добавлен тест самого runner: вывод и лог доступны до завершения набора, ненулевой код не скрывается, последующие наборы выполняются. Поведение `flash.cmd` не изменено.

### Безопасность очистки
- Добавлен TC-17 через CMD-обёртки: ResetConfig/Clean/DryRun, сохранность HEX, SHA-256, backups, CMD, документов и неизвестных инструментов; отказ при junction вместо удаляемого пути, внутри истории или в родительской `.tools`. Контрольная папка вне папки вызова проверяется по содержимому. Рабочий код очистки не изменён; тест автоматически включён в CI PS5.1/7.

### Ограничения ожидания
- Устранено зависание перечисления J-Link после выхода утилиты, если её потомок держит stdout/stderr открытыми: дочитывание ограничено 1000 мс после ожидания процесса до 10000 мс. Это не тайм-аут прошивки или всего `info`.
- Добавлен TC-22 с реальными тестовыми процессами: зависание, большой stdout/stderr, унаследованные каналы; оборудование и установленные движки не используются. Набор автоматически запускается в CI на PS5.1/7.

### DryRun
- Планирование вынесено до обнаружения оборудования: все команды с `-DryRun` обходятся без внешних утилит, USB/MCU, сети, ввода и изменения файлов. Показываются источники значений; неполный/ошибочный план возвращает 1, готовый — 0 без обещания аппаратного успеха.
- Добавлена базовая локальная проверка Intel HEX (записи, длина, контрольные суммы, EOF, данные) и SHA-256 при наличии. Совместимость с памятью MCU не проверяется. ТЗ обновлено до ревизии 1.4.
- Добавлены запретительные процессные проверки CMD в PS5.1/7, автоматически включаемые в CI. Исправлены передача кавычек для путей с пробелами и сохранение ненулевого кода завершения в CMD-загрузчике.

### CI
- При нескольких установках PowerShell runner выбирает первый executable в PATH вместо объединения путей в несуществующее имя команды.
- Исправлена ошибка валидации workflow до запуска заданий: оболочка шага фиксирована как pwsh, а версия PowerShell из матрицы передаётся runner через окружение и `-PowerShellExe`.
- Добавлен полный процессный тест ошибки J-Link для SEGGER и CubeProgrammer, RU/EN: код завершения, единственная попытка с явным serial, отчёт и история. Контрольная мутация проверяет обнаружение повтора без serial; MCU не используется.
- Проверки Windows запускаются при push в любую ветку/тег, pull request и вручную. Все `tests/Test-*.ps1` автоматически выполняются в PS5.1 и PS7 с отдельными логами и общим результатом; логи сохраняются на 14 дней. Добавлена строгая проверка ТЗ из версионируемой копии проверяющего скрипта.

### Документация
- AGENTS адаптирован под самодостаточный CMD-инструмент; сохранены ветки `<агент>/<задача>`, подписанные коммиты и порядок push/CI/land без PR. Добавлены TODO и RU/EN maintenance/HOWTO с известными командами; упрощены правила локальных исследований.
- В ТЗ ревизии 1.3 согласован отказ при ненайденном явном `-Serial` для flash: без выбора замены и обращения к чужому MCU. Добавлены TC-32–TC-34; на момент этой ревизии полный безопасный DryRun ещё не был реализован.
- В ТЗ ревизии 1.2 согласован Info с DryRun: только план без внешних утилит, USB-запросов и подключения к MCU даже при ProbeTarget. Добавлены TC-30–TC-31; реализация добавлена позднее, см. раздел DryRun выше.
- В ТЗ ревизии 1.1 закрыт вопрос неполного DryRun-плана: без ввода, коды 0/1, диагностика и необязательный serial. Добавлены требования и тест-кейсы; реализация добавлена позднее, см. раздел DryRun выше.
- Общее ТЗ приведено к структуре embedded-tech-spec: черновик ревизии 1.0, постоянные номера, происхождение требований, тест-кейсы, матрица и открытые вопросы. Прежнее частное ТЗ info ревизии 2 сохранено с таблицей переноса. Целевой DryRun и процедура сохранения/восстановления памяти отделены от реализованного поведения.

### Структура проекта
- Инструкция и правила тестирования перенесены в `docs/`; локальные исследования используют `docs/research/NN-name/`, ручные проверки - `tests/manual/NN-name/`. Локальные материалы исключены из Git и релиза.

### Исправлено
- Явный `-Serial` при прошивке больше не теряется при недоступном `st-info` и не заменяется другим программатором. Достоверно отсутствующий ST-Link отклоняется по USB-перечислению до опроса MCU; при неполном перечислении движок получает заданный serial. Добавлена регрессия выбора и аргументов для трёх движков в PS5.1/7.
- Тайм-аут J-Link обозначается отдельным сообщением в разделе USB-программаторов с советом проверить USB и повторить `info.cmd`; найденные ST-Link остаются в списке.
- `info.cmd` получает список ST-Link через CubeProgrammer `-l stlink-only`, предварительно проверяя поддержку ключа. При недоступности используется Windows USB.
- Идентификаторы экземпляра Windows больше не выдаются за серийные номера. Ошибки перечисления CubeProgrammer явно обозначаются; USB ID неизвестного устройства сохраняется для диагностики.
- Добавлены регрессионные тесты PowerShell 5.1/7, карточка справочника и ТЗ изменения, ревизия 1. Английское описание: CHANGELOG.en.md.

## [0.2.9] - 2026-09-24

### Added
- Added `erase.cmd`, `forget.cmd`, `backup.cmd` and `info.cmd` wrappers; implementation remains in `flash.cmd`.
- Added operation-specific `--help` (`-Help`, `-h`) and `--version` (`-Version`) for every command, exiting before discovery or file changes; covered by isolated CMD tests in PowerShell 5.1 and 7.
- Added full Flash erase with live probe selection, operation reports and history.
- Added Intel HEX backups with SHA-256, filenames containing date/time, MCU device ID and image size, and protection against overwriting existing backups.
- Added environment inventory and optional target inspection with `-Info -ProbeTarget`.
- Added settings reset and local artifact cleanup; backups and firmware files are preserved.
- Added hardware-free maintenance and backup tests for PowerShell 5.1 and 7.

### Changed
- Resolve local settings, tools and reports relative to the working directory.
- Include all command wrappers in the release archive.
- Mark the configured/automatically selected engine executable with `*` in environment info.
- Reuse installed OpenOCD with its matching scripts before downloading a local copy.
- Accept both capitalization variants of OpenOCD target voltage and capture st-info stderr warnings without aborting PowerShell 5.1.
- Return a nonzero exit code on operation failure even when the tool exits successfully without a completion marker.

## [0.2.8] - 2026-06-19

### Added
- Added SEGGER J-Link Commander support via `-Engine JLINK`.
- Added STM32CubeProgrammer J-Link probe mode via `-Probe JLINK`.
- Added `-Device` for explicit J-Link device names such as `STM32G431CB`.
- Added `.probe_type`, `.jlink_device`, and `.jlink_serial` persistence for J-Link workflows.
- Added J-Link log parsing for reports and history.

### Changed
- Made J-Link serial optional when only one J-Link probe is connected.
- Skipped CubeProgrammer `-rst` for `-Probe JLINK` to avoid failing after successful write and verify.
- Improved dry-run behavior so OpenOCD dry runs do not download OpenOCD.
- Updated README and Russian usage guide for J-Link workflows.

## [0.2.7] - 2026-05-28

### Changed
- Refactored tool log parsing into per-engine pattern tables to simplify future engine support.

## [0.2.6] - 2026-05-20

### Added
- Added per-session history storage in `.history` with timestamped reports and logs.
- Added `.history/index.html` with links to recent flashing sessions.
- Added a history link to the main HTML report.

## [0.2.5] - 2026-05-20

### Added
- Added SHA-256 verification for firmware `*.hex` files before flashing.
- Added support for reading expected SHA-256 from `-Sha256`, `*.hex.sha256`, or `*.sha256`.
- Added SHA-256 verification details to console output and the HTML report.

## [0.2.4] - 2026-05-13

### Added
- Added `st-info`-based STM32 detection for OpenOCD target auto-selection.
- Added support for choosing a specific ST-Link when multiple programmers are connected.
- Added `-Serial` parameter to select a programmer by its serial number.
- Added persistence of the selected programmer in `.stlink_serial`.

### Changed
- Updated OpenOCD flashing to bind to the selected ST-Link instead of using the first matching device.
- Added automatic OpenOCD serial-format fallback for Windows setups where plain serial matching is rejected.
- Updated README and Russian usage guide to document multi-probe selection and `st-info` behavior.

## [0.2.3] - 2026-04-25

### Changed
- Updated release publishing so GitHub Release pages use the matching `CHANGELOG.md` section as the release description.

## [0.2.2] - 2026-04-25

### Added
- Added `CHANGELOG.md` to the repository and release package.
- Added a separate `.sha256` checksum file to release assets.

### Changed
- Updated CI to require `CHANGELOG.md` as part of the tracked release documentation set.
- Updated the release workflow to package changelog and publish checksum assets alongside the zip archive.

## [0.2.1] - 2026-04-25

### Added
- Added CI workflow to validate required files, PowerShell syntax, and version format.
- Added release workflow to publish tagged GitHub Releases with packaged artifacts.
- Added script version display in the console banner and HTML report.
- Added operator, account, machine, and network host details to the HTML report.
- Added local and UTC timestamps to the HTML report.
- Added total operation duration to both console output and HTML report.
- Added a detailed Russian usage guide.

### Changed
- Improved auto-flash flow when a single `.hex` file is present or passed directly.
- Preferred STM32CubeProgrammer automatically for direct non-interactive flashing when available.
- Changed successful runs to save the report silently without opening the browser.
- Kept automatic report opening only for failed runs.
- Improved report readability with section highlighting and alternating row backgrounds.
- Normalized progress-bar garbage characters in captured tool logs for cleaner reports.
- Removed the final keypress wait from the batch wrapper.
- Shortened the flashing status message to avoid promising a fixed duration.
- Updated README to stay short, bilingual, and aligned with the current script behavior.

### Fixed
- Fixed relative `-HexFile` resolution before working directory initialization.
- Fixed crashes on non-numeric interactive menu input.
- Fixed repeated misinterpretation of `ru` and `en` as firmware paths.
- Fixed use of invalid saved or passed OpenOCD target configs.
- Fixed missing Russian localization for the MCU section title.

## [0.1.0] - 2026-04-25

### Added
- Initial public baseline of the single-file STM32 flashing script.
- Built-in Russian and English localization.
- Support for STM32CubeProgrammer and auto-downloaded OpenOCD.
- HTML flash report and text log generation.
