# TODO

## Текущее состояние

- Версия 0.2.9, ветка `codex/history-retention`. TC-20 слит в main (`8cc95d5`).
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.5.
- CI main успешен: run 37849036804 для `8cc95d5`.
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
  Текущая ветка ещё не опубликована.
  Новый релиз не подготовлен; аппаратные операции не выполнялись.

## Ближайшие шаги

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
- [ ] Зафиксировать `codex/history-retention`; затем push владельцем, CI и land.
- [ ] Перед аппаратной приёмкой согласовать подключённые платы и матрицу операций.

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
   коммита в main. Это ручное условие выпуска, не новая автоматизация workflow.

## Отложено

- Тайм-ауты записи/стирания, блокировки параллельных операций, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Current: version 0.2.9, branch `codex/history-retention`; TC-20 landed on main
at 8cc95d5 with successful main CI run 37849036804. Specification 1.5 is a draft.
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
This branch is not pushed, no release is prepared and no hardware operations ran.

Next: create the agreed history-retention commit; the owner pushes, checks CI and lands.
Then confirm connected boards and the hardware acceptance matrix before any MCU writes.
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
   This is a manual release gate, not a workflow change. Recheck any discovered defects.
