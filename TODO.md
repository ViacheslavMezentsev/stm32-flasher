# TODO

## Текущее состояние

- Ветка `codex/setup-command`: согласованы имя и сценарий setup.cmd; реализован
  мастер без MCU с подтверждением, отменой и ранним DryRun. Версия пока 0.2.10.
  Добавлены TC-36, тест setup и упаковка обёртки; все 14 наборов прошли в PS5.1/7
  09.10.2026, ТЗ strict без замечаний. Ожидается ручная проверка мастера владельцем.
- Опубликован [v0.2.10](https://github.com/ViacheslavMezentsev/stm32-flasher/releases/tag/v0.2.10), коммит `c2c9eb7`.
- CI рабочей ветки, main и тега, а также Release завершились успешно.
  ZIP и `.zip.sha256` прикреплены; RU/EN описание сохранено.
  Повторное скачивание релизного ZIP для независимой проверки SHA-256 не удалось
  из-за сетевой ошибки среды. Проверка локальной сборки выполнена отдельно.
- Для 0.2.10 все 13 наборов прошли в PS5.1/7 09.10.2026; ТЗ strict без замечаний.
- Описания релизов и новый workflow слиты в main (`0c9349b`), CI рабочей ветки и main успешен.
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.6.
- CI main и рабочей ветки успешен для `9c87c24`.
- Реализован ранний планировщик DryRun без утилит, USB/MCU, сети, ввода и записи.
  Базовая проверка Intel HEX согласована и добавлена. CMD сохраняет код ошибки
  PowerShell и кавычки в аргументах с пробелами.
- TC-22 выявил зависание чтения stdout/stderr J-Link после выхода процесса;
  добавлен лимит дочитывания 1000 мс. Лимит процесса остаётся 10000 мс.
- TC-17 дополнен CMD-тестами junction и сохранности пользовательских данных;
  рабочий код очистки не потребовал изменений. Symlink файлов и гонки не покрыты.
- Runner выводит строки в реальном времени, пишет UTF-8 логи и сохраняет
  DurationSeconds в results.json. Поведение flash.cmd не менялось.
- TC-20 дополнен 16 процессными сценариями с имитацией CubeProgrammer:
  flash/erase/backup, RU/EN, результат, HTML/JSON, время и политика браузера.
  Предыдущие 11 наборов прошли в PS5.1/7 09.10.2026.
  Исправлены перезапись архива в одну секунду и ссылка на историю в архивном HTML.
  Все 12 наборов прошли в PS5.1/7 09.10.2026; ТЗ strict без замечаний.
  На подтверждённой WeAct BluePill-Plus 128 КиБ
  проверены backup/erase/restore через CubeProgrammer и OpenOCD со ST-Link,
  через SEGGER Commander и CubeProgrammer с J-Link.
  После каждого цикла память побайтно совпала с исходной копией. Плата восстановлена.
  После Cube/J-Link потребовался отдельный reset; программа запущена через SEGGER.
  Проверены смешанное меню info и очистка отдельного стенда, см. docs/testing.md.

## Ближайшие шаги

- [x] Завершить проверки setup в PS5.1/7 (14 наборов), ТЗ strict.
- [ ] Ручная проверка мастера владельцем без прошивки.
- [ ] Согласовать коммит setup; push, CI и land после успешных проверок.
- [x] Согласовать AGENTS и памятки, проверить состав изменений; убрать реальные serial из новых тестов и публикуемых примеров.
- [x] Подготовить подписанные коммиты исправлений, CI и документации.
- [x] Предыдущая ветка опубликована и слита владельцем в main; локально подтверждён `f4ec9bd`.
- [x] Дополнить TC-32 полным запуском с имитацией ошибки J-Link: ненулевой код
  и отсутствие повторной попытки без явного serial.
- [x] Зафиксировать `codex/jlink-failure-regression`; push владельцем, успешный CI и land.
- [x] Начать `codex/safe-preview` от актуального main.
- [x] Согласовать вопрос 9.2.8 ТЗ: базовая проверка Intel HEX без проверки памяти MCU.
- [x] Реализовать безопасный DryRun; добавить CMD-регрессии TC-18–TC-19, TC-26–TC-31, TC-34–TC-35. Границы покрытия указаны в ТЗ.
- [x] Согласовать фиксацию изменений DryRun.
- [x] Push ветки DryRun владельцем, успешный CI и land.
- [x] Проверить зависшие процессы перечисления и пределы ожидания (TC-22).
- [x] Зафиксировать `codex/inventory-timeouts`; push владельцем, успешный CI и land.
- [x] Дополнить TC-17 проверкой junction, DryRun и сохранности пользовательских данных.
- [x] Зафиксировать `codex/cleanup-safety`; push владельцем, успешный CI и land.
- [x] Добавить потоковый вывод и длительности наборов в runner с регрессией.
- [x] Согласовать коммит `codex/ci-test-progress`; push владельцем, CI и land.
- [x] Дополнить TC-20: отчёты и история разных операций при успехе и ошибках.
- [x] Согласовать коммит `codex/report-history-tests` и план выпуска 0.2.10.
- [x] Зафиксировать `codex/report-history-tests`; push владельцем, CI и land.
- [x] Проверить накопление истории: несколько сессий, лимит индекса и переходы из архивных отчётов.
- [x] Согласовать коммит `codex/history-retention`.
- [x] Зафиксировать `codex/history-retention`; push владельцем, CI и land.
- [x] Согласовать WeAct BluePill-Plus и проверить циклы Cube/ST-Link, OpenOCD/ST-Link.
- [x] Переключить эту плату на J-Link, повторно идентифицировать и проверить цикл.
- [x] Проверить интерактивный выбор в info при нескольких отладчиках и clean на отдельном стенде.
- [x] Согласовать коммит результатов `codex/hardware-acceptance`.
- [x] Зафиксировать результаты приёмки; push владельцем, CI, land.
- [x] Подготовить краткую RU/EN заметку `docs/releases/v0.2.10.md` для ручного заполнения описания релиза.
- [x] Перевести Release на ручную публикацию владельцем и автоматическое прикрепление ZIP/SHA-256 без изменения текста.
- [x] Поднять версию до 0.2.10; оформить RU/EN CHANGELOG и README.
- [x] Проверить ZIP из release workflow: 14 файлов, совпадение с исходниками и SHA-256;
  справка/версия всех пяти команд в пакете на RU/EN (20 проверок), без MCU.
- [x] Завершить регрессии PS5.1/7 (13 наборов в каждой оболочке) и проверку ТЗ strict.
- [x] Подписанный коммит подготовки выпуска (`c2c9eb7`).
- [x] Push владельцем, успешный CI, land и успешный CI итогового main.
- [x] Вручную опубликовать v0.2.10 с текстом из docs/releases/v0.2.10.md;
  проверить результат Release workflow и наличие ZIP/SHA-256.
- [ ] Независимо скачать опубликованные ZIP/SHA-256 и проверить контрольную сумму.
- [ ] После setup согласовать защиту от параллельных операций. Предлагается
  начать с блокировки папки вызова и тестов двух процессов без MCU; область
  блокировки, поведение второго запуска и отдельная защита программатора требуют согласования.

## План выпуска 0.2.10

Согласован стабилизирующий выпуск без новых функций. Этапы выполняются
последовательно; выявленные ошибки требуют исправления и повторной проверки.

1. Зафиксировать проверки TC-20: подписанный коммит, push владельцем, успешный CI, land.
2. Проверить накопление истории: несколько сессий, одинаковая секунда запуска,
   лимит индекса и переходы из архивных отчётов. Исправления сопровождать тестами.
3. Провести аппаратную приёмку ST-Link/J-Link и выбора из нескольких отладчиков,
   flash/backup/erase. Перед опытом согласовать конкретные платы и операции,
   сохранить и проверить всю затрагиваемую память; после опыта, включая ошибку,
   восстановить и проверить её. Очистку проверять только на отдельном стенде.
4. Обновить версию до 0.2.10, документацию и CHANGELOG. Проверить ZIP, справку
   всех команд и SHA-256. Владелец выпускает тег после успешного CI итогового
   коммита в main и вручную публикует релиз. Workflow прикладывает ZIP/SHA-256;
   успешный CI остаётся ручным условием выпуска.

## Отложено

- Тайм-ауты записи/стирания, блокировки параллельных операций, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Branch `codex/setup-command`: the setup name and scenario are agreed; implemented
the no-MCU wizard with confirmation, cancellation and early DryRun. Version remains
0.2.10. Added TC-36, tests and packaging; all 14 suites passed in PS5.1/7 on
2026-10-09, with a clean strict spec check.
Next: owner wizard test without flashing, then commit the remaining test/documentation changes.

Current: v0.2.10 published from c2c9eb7. Branch, main and tag CI and the Release
workflow succeeded. ZIP and SHA-256 assets are attached; RU/EN notes are preserved.
Downloading the published ZIP for independent checksum verification failed due
to an environment network error; the local build was checked separately.
Release notes and workflow landed on main at 0c9349b with successful branch/main CI.
Acceptance results landed at 9c87c24. Specification 1.6 is a draft.
Early DryRun planning avoids tools, USB/MCU, network access, prompts and writes.
Basic Intel HEX validation was agreed and implemented; MCU compatibility is not checked.
CMD preserves quoted paths and nonzero exit codes. TC-22 reproduced an unbounded
J-Link output drain after process exit; draining is now limited to 1000 ms.
TC-17 now covers CMD cleanup, junction rejection and user-data preservation;
cleanup implementation is unchanged. File symlinks and races remain outside coverage.
The runner streams output, writes UTF-8 logs and records DurationSeconds in JSON.
TC-20 adds 16 mocked CubeProgrammer scenarios for flash/erase/backup, RU/EN,
results, HTML/JSON, timestamps and browser policy. The new suite passed in
PS5.1/7; all 11 suites passed on 2026-10-09, with a clean strict spec check.
Same-second archive overwrites and archived history links are now fixed.
All 12 suites passed in PS5.1/7 on 2026-10-09; the strict spec check is clean.
CI discovers the suite automatically.
CubeProgrammer 2.19.0 and
OpenOCD 0.12.0 passed ST-Link backup/erase/restore on the confirmed WeAct
BluePill-Plus, 128 KiB. SEGGER Commander V8.32 and CubeProgrammer 2.19.0 also
passed memory backup/erase/restore via J-Link V9.60. Reads match the original bytes
after each cycle; the board is restored. Cube/J-Link needed a separate reset to
start the application, now running. Option bytes and protection were not changed.

The mixed-probe info menu and cleanup in a separate fixture passed.
The bilingual docs/releases/v0.2.10.md is prepared for manual use. The owner publishes
the release; the workflow attaches ZIP/SHA-256 without changing its title or body.
Version, README and RU/EN changelogs are prepared. The workflow-built ZIP has 14
files matching their sources and a verified SHA-256. All five packaged commands
passed RU/EN help/version checks (20 checks) without hardware.
All 13 suites passed in PS5.1/7 for 0.2.10 on 2026-10-09; the strict spec check is clean.
Next: independently download and verify the published ZIP/SHA-256, then agree
concurrent-operation protection. Proposed first scope: calling-directory locking
and two-process tests without hardware. Lock scope, second-run behavior and
separate probe protection still need agreement; implementation has not started.
Write/erase timeouts, locking, new engines/profiles and CI-gated releases remain
separate follow-ups.

Agreed 0.2.10 stabilization plan, without new features:

1. Commit TC-20 tests; owner pushes, checks CI and lands.
2. Check multiple history sessions, same-second names, index limit and archived links;
   accompany fixes with regression tests.
3. Run hardware acceptance for ST-Link/J-Link, multiple probes and flash/backup/erase.
   Confirm boards and operations first; back up and verify all affected memory,
   then restore and verify even after failure. Test cleanup in a separate fixture.
4. Bump to 0.2.10, update documentation/changelogs, check ZIP contents, all command
   help and SHA-256. Owner tags only after successful CI for the final main commit.
   The owner publishes manually; the workflow attaches ZIP/SHA-256. CI remains a
   manual release gate. Recheck any discovered defects.
