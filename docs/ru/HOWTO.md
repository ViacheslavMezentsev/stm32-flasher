# Памятка

[English](../en/HOWTO.md). Примеры — PowerShell из корня клона, если не указано иное.
Это команды для ручного запуска, не разрешение агенту выполнять push или аппаратные операции.

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
CI не проверяет физический SWD, reset или восстановление платы; release пока
не блокируется результатом CI автоматически.

## Рабочая папка и обзор

```powershell
New-Item -ItemType Directory -Force tests/manual/01-probe-inventory
Set-Location tests/manual/01-probe-inventory
$tool = (Resolve-Path ../../..).Path
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
Не переносите гарантии `forget -DryRun` на остальные режимы: общий безопасный
DryRun ещё не реализован.
