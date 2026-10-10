# Памятка

[English](../en/HOWTO.md). Примеры — PowerShell из корня клона, если не указано иное.
Это команды для ручного запуска, не разрешение агенту выполнять push или аппаратные операции.

## Единая конфигурация

Ручной setup с JSON проверяйте в новой пустой папке, вызывая setup/info по
полному пути из `bin`. Выберите OpenOCD, конкретный ST-Link, target вашей платы,
подтвердите `y`. Проверьте JSON и info, запомните SHA-256 JSON. Повторите setup
с CubeProgrammer, но отмените Enter на последнем подтверждении: хеш должен
сохраниться. Затем подтвердите смену: engine должен измениться, openocdTarget
очиститься. Вернитесь к OpenOCD с явным target. После каждого вызова сразу
проверяйте код возврата. Setup перечисляет USB, но не подключается к MCU;
прошивку для этого теста не запускайте. Владелец подтвердил сохранение OpenOCD,
info, отмену по SHA-256, переход на CubeProgrammer и возврат на OpenOCD с target
(exit 0 и повторное чтение через info).

Настройки запуска: [формат .flash.json и переход со старых файлов](../reference/launch-configuration.md).
Для предварительного просмотра используйте `info.cmd` или `setup.cmd -DryRun`:
они не мигрируют файлы. `setup.cmd` сохраняет JSON только после подтверждения.
При ошибке JSON сначала исправьте файл; намеренный сброс: `flash.cmd -ResetConfig`.
Просмотр списка удаления без сброса: `flash.cmd -ResetConfig -DryRun`.

## Сравнение с памятью MCU

В папке прошивки: `check.cmd -DryRun`, затем `check.cmd` для чтения и сравнения.
Эквивалент: `flash.cmd -Command check -HexFile firmware.hex`.
В PowerShell используйте `./check.cmd`, в CMD можно просто `check`.
Название не пересекается со встроенным `verify` в CMD.
При нескольких HEX укажите `-HexFile`; настройки движка/программатора берутся
из `.flash.json`, явные ключи имеют приоритет. OpenOCD требует сохранённый
target либо `-Target target/stm32f1x.cfg`; J-Link — device.
Ядро может остаться остановленным. Нет неявной записи, стирания, сброса или запуска.
Проверяются только байты HEX, не вся Flash. Доступность и поведение конкретной
платы необходимо проверить отдельно; для силовых устройств остановка тоже опасна.

## Управление ядром

В папке проекта начните с `halt.cmd -DryRun`. Реальное управление:
`halt.cmd` останавливает ядро, `go.cmd` продолжает без сброса, `reset.cmd`
сбрасывает MCU и запускает выполнение. Последняя команда не сбрасывает настройки.
Эквивалент: `flash.cmd -Command halt` (или go/reset). HEX не нужен и не читается.
Настройки берутся из `.flash.json`; явные ключи имеют приоритет. При нескольких
отладчиках без закреплённого serial появляется меню; при одном serial необязателен.

OpenOCD/ST-Link требует сохранённый или явный `-Target`, SEGGER/J-Link — `-Device`.
CubeProgrammer/ST-Link поддерживает halt/reset; go и CubeProgrammer/J-Link пока
отклоняются без смены движка. Для J-Link выбирайте `-Engine JLINK` явно или через setup.
Успех отражает ответ о состоянии ядра в момент проверки, а не исправность приложения.
Периферия/watchdog могут продолжать работать при halt. На силовой плате даже
остановка может быть опасна. Сначала согласуйте безопасный аппаратный стенд.

OpenOCD может сообщить о снижении частоты адаптера (`Unable to match requested
speed ... using ...`): сама эта информационная строка не означает отказ.
После отключения утилиты ядро может изменить состояние. Если отдельный go
возвращает `target not halted`, не повторяйте автоматически reset: он перезапустит
приложение, а не продолжит прежний PC. Сначала оцените состояние и безопасность платы.

## Git: рабочий цикл без PR

Сначала проверить незавершённую работу:

```powershell
git status --short --branch
git diff --stat
git diff --check
```

Новую ветку создавать только с чистым рабочим деревом после завершения текущей:

```powershell
git fetch origin
git switch main
git merge --ff-only origin/main
git switch -c codex/task-name
```

После тестов добавляйте файлы явно, проверяйте staged diff и подпишите коммит:

```powershell
git add -- AGENTS.md TODO.md docs/ru/maintenance.md docs/en/maintenance.md
git diff --cached
git commit -S -m "docs: document contributor workflow"
```

Список файлов выше только пример, не полный состав текущего изменения.
Диагностика подписи без изменения настроек:

```powershell
git config --get commit.gpgsign
git config --get gpg.format
git config --get user.signingkey
```

Владелец публикует рабочую ветку, проверяет успешный CI именно этого коммита,
затем выполняет land с чистым деревом:

```powershell
$branch = git branch --show-current
git push -u origin $branch
# Дождаться успешного CI, проверить diff и наличие нужных коммитов.
git config --get alias.land
git land $branch
```

`git land` — локальный alias, не встроенная команда Git. Проверенная на текущей
машине последовательность: fetch, switch main, fast-forward origin/main,
fast-forward рабочей ветки, `git push --atomic origin main :<branch>`, удаление
локальной ветки. Alias не запускает тесты и не ждёт CI. Не передавайте `main`
как рабочую ветку. Если alias отсутствует или отличается, остановитесь;
не устанавливайте его вслепую. При расхождении истории не используйте force push.

## Автоматические проверки

Основной запуск без аргументов проверяется отдельно:
`pwsh -NoProfile -File tests/Test-FlashEntry.ps1` (либо Windows PowerShell).
Набор запускает настоящие CMD/EXE-процессы с заглушками трёх движков, без MCU.
Не заменяйте этот сценарий вызовом с `-Lang` или `-HexFile`: непустые аргументы
скрывали регрессию issue #1 в 0.2.10–0.2.11. Исправление поставляется в 0.2.12;
для обновления замените flash.cmd, сохранив настройки проекта.

Локализация без оборудования: `pwsh -NoProfile -File tests/Test-Localization.ps1`.
Для Windows PowerShell используйте `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Localization.ps1`.
Проверяются основные словари,
индексы подстановок и буквальные ключи T; Test-Help проверяет справку на RU/EN.
Язык задаётся для каждого вызова (`info.cmd -Lang en`), не сохраняется между ними.
Переменные PowerShell, например `$repo`, необходимо задавать в каждом окне отдельно.

Проверить тайм-ауты перечисления без оборудования (TC-22):

```powershell
pwsh -NoProfile -File tests/Test-InventoryTimeout.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-InventoryTimeout.ps1
```

Тест компилирует временный EXE штатным Windows PowerShell/.NET Framework;
дополнительный SDK не требуется. Проверяются зависание процесса и удержание
stdout/stderr потомком, в том числе по отдельности. Тайм-аут перечисления
не ограничивает время прошивки и не является лимитом всего `info.cmd`.

Если после push нет заданий, откройте Actions → нужный запуск → Annotations.
Ошибка `Invalid workflow file` возникает до выдачи Windows runner; повтор тестов
локально её не проверяет. Для матрицы версий используйте фиксированный `shell: pwsh`,
значение матрицы передавайте через `env` в `Invoke-Tests.ps1 -PowerShellExe`.
Проверка YAML не равна проверке допустимости контекстов выражений GitHub Actions.

Отдельно воспроизвести отказ J-Link без платы и установленных движков:

```powershell
pwsh -NoProfile -File tests/Test-JLinkFailure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-JLinkFailure.ps1
```

Временная копия подменяет внешние вызовы; рабочий `flash.cmd` не меняется.
Включён контроль с намеренно отключённой защитой от повтора без serial.

Полный комплект:

```powershell
pwsh -NoProfile -File tests/Invoke-Tests.ps1 -LogDirectory tests/.tmp-ci-logs-pwsh
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1 -LogDirectory tests/.tmp-ci-logs-ps51
python -X utf8 tests/tools/check_spec.py docs/TECHNICAL_SPECIFICATION.md --strict
```

Логи и `results.json` находятся в указанных каталогах. В GitHub Actions логи
доступны в артефактах заданий. Подробнее: [testing](../testing.md).
Runner выводит строки по мере поступления, после набора — PASS/FAIL, длительность
и exit code. Поле `DurationSeconds` сохраняется в JSON. Пауза возможна, если сам
тест ничего не пишет: например, ожидает тайм-аут. Повторять запуск только из-за
паузы в выводе не нужно; проверьте состояние задания в Actions.
CI не проверяет физический SWD, reset или восстановление платы; release пока
не блокируется результатом CI автоматически.

## Рабочая папка и обзор

```powershell
New-Item -ItemType Directory -Force tests/manual/01-probe-inventory
Set-Location tests/manual/01-probe-inventory
$tool = (Resolve-Path ../../../bin).Path
# Команды можно вызывать отсюда или скопировать к прошивке:
# Copy-Item "$tool/*.cmd" $firmwareDirectory
# Рабочая папка, настройки и история определяются местом вызова.
& "$tool/info.cmd" --help
& "$tool/flash.cmd" --version
& "$tool/info.cmd"
```

Последняя команда перечисляет USB; `-ProbeTarget` уже подключается к MCU.
При тайм-ауте J-Link проверьте USB-хаб, питание и повторите обзор. Тайм-аут
сам по себе не доказывает неисправность MCU. Windows ID вида `7&...` не serial.

## SHA-256 и явная прошивка

В папке с собственным `mcu_lts_board.hex` создайте sidecar:

```powershell
$file = Get-Item .\mcu_lts_board.hex
$hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($file.FullName + '.sha256') -Encoding ASCII -Value "$hash *$($file.Name)"
```

Это фиксация хеша имеющегося файла, а не доказательство доверенного происхождения.
Дальнейшие команды пишут в MCU. Перед экспериментом сначала сделайте пригодную
копию всей затрагиваемой памяти. `$serial` задайте по свежему обзору вручную:

```powershell
$serial = Read-Host 'Serial выбранного программатора'
& "$tool/flash.cmd" -HexFile .\mcu_lts_board.hex -Engine OPENOCD -Probe STLINK -Serial $serial -Target target/stm32g4x.cfg
# Альтернатива для подтверждённого STM32G431CB через J-Link:
& "$tool/flash.cmd" -HexFile .\mcu_lts_board.hex -Engine JLINK -Serial $serial -Device STM32G431CB
```

Выберите одну подходящую команду, не запускайте блок целиком для разных плат.
HEX и MCU должны соответствовать друг другу. Явный serial не заменяется другим.

## Копия и восстановление BluePill

Только для подтверждённого STM32F103C8 с пользовательской Flash 64 КиБ и J-Link:

```powershell
& "$tool/backup.cmd" -Engine JLINK -Serial $serial -Device STM32F103C8 -Size 65536 -Output backups/before.hex
```

До стирания проверьте успешное чтение, полный диапазон и SHA-256, по возможности
повторным чтением сравните байты. Сохраните копию и логи отдельно от опыта.
Если память защищена или размер не подтверждён, не стирайте.

Только после отдельного разрешения на опыт:

```powershell
& "$tool/erase.cmd" -Engine JLINK -Serial $serial -Device STM32F103C8
```

После опыта восстановите исходный образ, в том числе после неудачного опыта:

```powershell
& "$tool/flash.cmd" -HexFile backups/before.hex -Engine JLINK -Serial $serial -Device STM32F103C8
```

Проверьте верификацию, повторное чтение/побайтовое совпадение и отдельно запуск
приложения. Если восстановление не удалось, прекратите опыты и сообщите владельцу.

## Очистка папки вызова

```powershell
& "$tool/forget.cmd" -DryRun
& "$tool/flash.cmd" -ResetConfig
# При необходимости удалить также логи, отчёты и скачанные инструменты:
& "$tool/forget.cmd"
```

Первый вызов только показывает удаления; второй удаляет настройки; последний
удаляет артефакты, но сохраняет backups и входные прошивки. Проверьте текущую папку.

При `Linked cleanup path/content` найдена ссылка в удаляемом пути. Не удаляйте
её цель ради продолжения очистки. Сначала разберите структуру каталогов и повторите
DryRun. Ошибка не означает откат уже выполненных удалений; не меняйте ссылки
параллельно с очисткой. Регрессия на временном стенде без пользовательских данных:

```powershell
pwsh -NoProfile -File tests/Test-CleanupSafety.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-CleanupSafety.ps1
```

## Проверка отчётов без оборудования

```powershell
pwsh -NoProfile -File tests/Test-ReportHistory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-ReportHistory.ps1
pwsh -NoProfile -File tests/Test-HistoryRetention.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-HistoryRetention.ps1
```

Тест имитирует CubeProgrammer, проверяет отчёты flash/erase/backup на RU/EN
и перехватывает браузер. MCU и установленные инструменты не используются.
Артефакты создаются во временном стенде внутри tests и удаляются после прогона.
Это не аппаратная проверка и не проверка отображения HTML в браузере.

История: последние 20 строк индекса не означают удаление старых файлов.
Суффикс `_1`, `_2` у архива означает занятое имя, а не повтор операции на MCU.
Новые архивные отчёты ссылаются на соседний `index.html`; старые не мигрируются.
Запускайте операции последовательно: суффиксы не заменяют блокировку процессов.

## Перенастройка

Запустите `setup.cmd` из папки проекта: выберите движок, затем тип и программатор,
при необходимости target OpenOCD или device J-Link. Подтвердите итог буквой `y`.
`q` или пустой ответ в меню отменяет мастер; пустой target/device откладывает
определение/запрос до операции. Пустое подтверждение означает отмену.

«STLINK | Авто» и «JLINK | Авто» сохраняют тип, но не serial. Сохранение заменяет
шесть настроек целиком, убирая старые serial и неиспользуемые target/device.
Перед выбором показаны прежние значения; для сохранения target/device введите их снова.
При нескольких устройствах выбранного типа последующая операция потребует выбора.
Мастер показывает USB-названия, не определяет модель MCU и не проверяет совместимость прошивки.
OpenOCD допускается без установки; загрузка, если нужна, произойдёт только при операции.

`setup.cmd -DryRun` показывает настройки и план мастера без ввода, опроса USB,
запуска утилит, сети и записи. `--help`/`--version` доступны как обычно.
Мастер интерактивный: ключи выбора движка/программатора и `-Silent` с ним несовместимы.
HEX, backups, история, отчёты и инструменты не затрагиваются. Отмена возвращает 0,
ошибочный ввод/ошибка сохранения — 1. При обработанной ошибке записи выполняется
откат настроек; это не защита от аварийного завершения или потери питания.

## Параллельные запуски

Рабочие операции flash/erase/backup/setup/forget/ResetConfig и `info -ProbeTarget`
занимают папку до завершения. Второй запуск сразу возвращает 1 и просит дождаться
окончания операции, не меняя файлы и не обращаясь к оборудованию. Другая папка
независима. `--help`, `--version`, все `-DryRun` и обычный `info` доступны;
базовый info при этом может увидеть настройки в процессе сохранения.

Ручная проверка без MCU: в первом терминале оставьте `setup.cmd` на первом меню,
во втором из той же папки запустите `setup.cmd` (ожидается код 1), затем
`setup.cmd --help` (код 0). Ответьте `q` в первом терминале; новый запуск setup
должен снова открыть меню. Не выбирайте аппаратную операцию ради проверки блокировки.

Ничего удалять для снятия блокировки не нужно. Используется именованный
[mutex Windows](https://learn.microsoft.com/en-us/dotnet/api/system.threading.mutex?view=netframework-4.8),
освобождаемый при завершении процесса. Ошибка доступа к mutex означает отказ
операции, а не обход защиты. Не завершайте активную прошивку ради снятия блокировки.
После аварии проверьте дочернюю утилиту и состояние MCU: mutex не останавливает
потомков и не восстанавливает прерванную запись или настройки.

Область: один ПК и нормализованный абсолютный путь без учёта регистра. Junction,
SUBST, сетевые псевдонимы и запуск с другого ПК не объединяются. Старые версии,
внешние утилиты и один программатор из разных папок не защищены этим механизмом.
Используйте одинаковый путь к папке; с одним программатором работайте последовательно.

## Краткое описание релиза

Храните текст в `docs/releases/v<версия>.md`: краткое описание на русском,
затем тот же текст на английском в `<details><summary>English</summary>`.
Подробный CHANGELOG давайте абсолютной ссылкой на тег выпуска: RU —
`CHANGELOG.md`, EN — `CHANGELOG.en.md`. Ссылки на будущий тег заработают после публикации.

1. Слить подготовку выпуска в main и дождаться успешного CI именно этого коммита.
2. В GitHub Releases создать новый релиз: тег `v<версия>` на проверенном коммите,
   заголовок `stm32-flasher <версия>`, описание из подготовленного файла.
   Версия тега должна совпадать с `$VERSION` в `flash.cmd`.
3. Нажать Publish release. Сохранение черновика и простой push тега сборку не запускают.
4. Дождаться успешного workflow Release: он прикладывает ZIP и `.zip.sha256`
   к уже опубликованному релизу. До завершения сборки этих файлов может не быть.

Workflow не создаёт релиз и не меняет заголовок или описание. При ошибке смотрите
Actions; после устранения внешнего сбоя можно повторить запуск. Одноимённые вложения
заменяются (`--clobber`), остальные сохраняются. Если ошибка в коде, подготовьте
новый исправленный тег; не перемещайте уже опубликованный тег.
Проверка CI перед выпуском остаётся ручной обязанностью владельца.
Этот порядок рассчитан на обычные, не immutable releases: для неизменяемых релизов
вложения нужно подготовить до публикации, что требует другого workflow.

Справка: [событие release](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release),
[загрузка вложений](https://cli.github.com/manual/gh_release_upload).

## Предварительный план без оборудования

```powershell
& "$tool/flash.cmd" -DryRun -HexFile firmware.hex -Engine OPENOCD -Target target/stm32f1x.cfg
& "$tool/erase.cmd" -DryRun -Engine JLINK -Device STM32F103C8
& "$tool/backup.cmd" -DryRun -Engine JLINK -Device STM32F103C8 -Size 65536
& "$tool/info.cmd" -DryRun -ProbeTarget -Engine JLINK -Device STM32F103C8
$LASTEXITCODE
```

DryRun не запускает утилиты, не опрашивает USB/MCU и не меняет файлы. Проверка HEX
локальная: формат и контрольные суммы, не соответствие плате. Код 0 означает
готовый план; 1 — ошибку или нехватку данных без меню. Serial необязателен,
target/device берутся из CLI или настроек; размер backup задаётся явно.
CMD передаёт ненулевой код PowerShell вызывающему процессу; пути с пробелами
заключайте в кавычки. Не убирайте DryRun, пока не проверены плата и разрешение на опыт.
