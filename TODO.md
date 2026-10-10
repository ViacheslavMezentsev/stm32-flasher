# TODO

## Текущее состояние

- `codex/control-commands`: первый подэтап — verify через чтение и сравнение
  диапазонов HEX, без записи/стирания/сброса/автоматического запуска.
  Добавлены обёртка, отчёт, история и Test-Verify с EXE-заглушками трёх движков.
  Прежние 19 наборов прошли в PS5.1/7; Test-Verify после исправлений тестового
  сценария прошёл отдельно: 72 случая в каждой версии. ТЗ strict без замечаний.
  Аппаратная проверка отложена по указанию владельца; MCU не использовался.
  halt/go/reset остаются следующим отдельным подэтапом. Версия пока 0.2.12.
- `codex/json-config` слит в main (`d9027c3`); через GitHub API подтверждены
  успешные CI рабочей ветки и main, удаление рабочей ветки на GitHub.

- Этап `codex/json-config`: реализован согласованный `.flash.json`, schemaVersion 1.
  Перенос при рабочем запуске/подтверждении setup, справочные режимы не мигрируют.
  Добавлен Test-LaunchConfig; 10.10.2026 все 19 наборов прошли в PS5.1/7,
  ТЗ strict и синтаксис без ошибок. Формат и миграция описаны на RU/EN.
  Автотесты выполнялись без MCU; версия остаётся 0.2.12 до подготовки 0.3.0.
  Владелец подтвердил перенос в JSON и успешную прошивку через
  CubeProgrammer/ST-Link (3.406 с). Реализация закоммичена: `fc4d679`.
  Владелец также подтвердил чтение готового JSON через info: источник настроек,
  выбранный движок и подключённый ST-Link совпадают, сообщения о переносе нет.
  Ручная проверка setup, результат CI и land пока не подтверждены.
- `codex/bin-layout` слит владельцем в main (`6d36d9a`); завершение CI подтверждено
  владельцем. Начальная запись ниже сохраняет историю подготовки.

- Начат этап `codex/bin-layout` для 0.3.0: CMD перенесены в `bin`.
  В ZIP остаются в корне; применение копированием к HEX сохраняется.
  Новый тест выявил отсутствие кавычек у пути HEX в аргументах CubeProgrammer;
  основная и резервная команды исправлены, обёртки не менялись.
  Версия скрипта пока 0.2.12. 10.10.2026 все 18 наборов прошли в PS5.1/7,
  включая 28 сценариев CMD и упаковку ZIP; синтаксис и ТЗ strict без ошибок.
  Оборудование не использовалось. Коммит, push и CI GitHub ещё предстоят.
- Владелец выпустил v0.2.12. Следующая согласованная цель — 0.3.0:
  единый `.flash.json`, команды halt/go/reset/verify и переносимое применение.
  Реализация JSON описана выше; новые команды пока не реализованы.

- Срочное исправление issue #1 в `codex/no-args-hotfix`, подготовка 0.2.12.
  Сравнение с 0.2.9 подтвердило регрессию CMD в 0.2.10–0.2.11 (`6867e44`):
  пустая FLASH_ARGS портила запуск. Правка ограничена обработкой аргументов.
  Новый Test-FlashEntry воспроизвёл ошибку до исправления и прошёл 14 сценариев
  с EXE-заглушками CubeProgrammer/OpenOCD/J-Link в PS7 после исправления.
  Все 17 наборов прошли в PS5.1/7 10.10.2026; ТЗ strict без замечаний.
  Локальный ZIP проверен: 15 файлов совпали с исходниками, SHA-256,
  24 вызова help/version и неизменённый CMD без аргументов в папке без HEX.
  Агент не выполнял операций с MCU. Владелец подтвердил исходный запуск без
  аргументов: единственный HEX, CubeProgrammer/ST-Link, успешные запись и проверка,
  длительность 3.584 с. Впоследствии владелец выпустил v0.2.12.
- Опубликован [v0.2.11](https://github.com/ViacheslavMezentsev/stm32-flasher/releases/tag/v0.2.11),
  коммит `2277d45`. CI рабочей ветки, main и тега успешен, включая 16 наборов
  в Windows PowerShell 5.1 и PowerShell 7. Release завершился успешно;
  ZIP (97 730 байт) и `.zip.sha256` прикреплены, RU/EN описание сохранено.
- Локальная сборка 0.2.11 проверена отдельно: 15 файлов, SHA-256 и 24 RU/EN
  вызова help/version. Дополнительные ручные сценарии подтверждены владельцем.
  Независимое скачивание опубликованного ZIP 09.10.2026 снова остановилось
  на сетевой ошибке среды «Требуемый адрес для своего контекста неверен».
  Метаданные GitHub не заменяют проверку байтов скачанного архива.
- Блокировка папки слита в main (`5e2c508`), CI ветки и main успешен. По логам владельца подтверждены
  выбор CubeProgrammer/ST-Link, переход на J-Link, отмена на первом меню
  с сохранением настроек и отказ второго setup с кодом 1. MCU не изменялся.
- Этап `codex/directory-lock`: согласована и реализована блокировка папки для рабочих
  операций; второй запуск завершается с кодом 1. Help/version, DryRun и базовый info доступны.
  Добавлен TC-37; все 15 наборов прошли в PS5.1/7 09.10.2026, ТЗ strict без замечаний.
  На этом этапе версия была 0.2.10; аппаратные операции не выполнялись.
- Setup слит в main (`d34347f`), CI ветки и main успешен; реализован
  мастер без MCU с подтверждением, отменой и ранним DryRun. На этом этапе версия была 0.2.10.
  Добавлены TC-36, тест setup и упаковка обёртки; все 14 наборов прошли в PS5.1/7
  09.10.2026, ТЗ strict без замечаний. Объём ручной проверки указан в docs/testing.md.
- Опубликован [v0.2.10](https://github.com/ViacheslavMezentsev/stm32-flasher/releases/tag/v0.2.10), коммит `c2c9eb7`.
- CI рабочей ветки, main и тега, а также Release завершились успешно.
  ZIP и `.zip.sha256` прикреплены; RU/EN описание сохранено.
  Повторное скачивание релизного ZIP для независимой проверки SHA-256 не удалось
  из-за сетевой ошибки среды. Проверка локальной сборки выполнена отдельно.
- Для 0.2.10 все 13 наборов прошли в PS5.1/7 09.10.2026; ТЗ strict без замечаний.
- Описания релизов и новый workflow слиты в main (`0c9349b`), CI рабочей ветки и main успешен.
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.10.
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

- [x] Проверить перенос в bin: все 18 наборов PS5.1/7, ZIP, ТЗ strict.
- [x] Зафиксировать `codex/bin-layout`: коммит, push, успешный CI, land.
- [x] Отдельным этапом внедрить `.flash.json`: версию схемы, валидацию,
  приоритет явных параметров и безопасную миграцию прежних файлов настроек.
  Повреждённая конфигурация не должна приводить к неявному выбору другого MCU.
- [x] Проверить info вручную, зафиксировать `codex/json-config`; push, CI, land.
- [ ] Дополнительная ручная проверка setup после перехода на JSON.
- [ ] Добавить тонкие halt/go/reset/verify через `-Command` в flash.cmd.
  halt останавливает ядро; go продолжает без сброса; reset сбрасывает и запускает;
  verify только сравнивает память с HEX, не исправляет прошивку и не заменяет SHA-256.
  Поддержку и побочные эффекты каждой операции проверить отдельно по движкам;
  неподдерживаемые сочетания отклонять явно, без скрытой смены движка.
- [ ] Проверить новые команды заглушками через настоящий CMD, включая ошибки,
  RU/EN, выбор из нескольких отладчиков и отсутствие нежелательных операций.
- [ ] После согласованных аппаратных проверок с backup/restore подготовить 0.3.0.

- [x] Завершить 17 наборов PS5.1/7 и ТЗ strict для 0.2.12.
- [x] Проверить локальный пакет 0.2.12.
- [x] Подтвердить исходный сценарий владельцем перед публикацией (CubeProgrammer/ST-Link).
- [ ] Подписанный коммит исправления; push, успешный CI, land и CI main.
- [ ] Выпустить новый тег v0.2.12, не менять опубликованные теги; проверить Release.
- [ ] После подтверждения результата закрыть issue #1 владельцем.
- [x] Проверить 0.2.11 в PS5.1/7, ТЗ strict и состав релизного ZIP.
- [x] Коммит подготовки 0.2.11 (`2277d45`); push владельцем, успешный CI, land и CI main.
- [x] Владелец опубликовал v0.2.11; Release успешен, ZIP/SHA-256 присутствуют.
- [ ] Независимо скачать ZIP/SHA-256 v0.2.11 и проверить контрольную сумму.
- [ ] Зафиксировать итог выпуска: `codex/release-0.2.11-outcome`, push, CI, land.
- [ ] Согласовать следующий этап: проверка успешного CI именно коммита тега
  перед сборкой/загрузкой assets. Ручная публикация и описание остаются у владельца;
  при отсутствующем, незавершённом или неуспешном CI workflow должен отказать.
  Это не предотвращает создание страницы релиза; до повторного успешного запуска
  на ней может не быть assets. Реализация пока не начата.
- [x] Завершить регрессии блокировки папки в PS5.1/7 (15 наборов) и проверку ТЗ.
- [x] Коммит блокировки папки слит в main (`5e2c508`).
- [x] Завершить проверки setup в PS5.1/7 (14 наборов), ТЗ strict.
- [x] Ручная проверка выбора, смены движка, отмены на первом меню и отказа второго setup.
- [x] Дополнить ручную проверку: help/info при блокировке, отмена перед сохранением,
  повторный запуск после освобождения папки.
- [x] Коммиты setup слиты в main, CI ветки и main успешен (`d34347f`).
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
- [x] Согласована блокировка папки: отказ второго запуска без ожидания, освобождение
  системой без lock-файла; справка/DryRun/базовый info доступны. Защита программатора отдельно.

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

- Тайм-ауты записи/стирания, блокировка программатора из разных папок, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Urgent issue #1 fix on `codex/no-args-hotfix`, preparing 0.2.12. Comparison with
0.2.9 confirmed a CMD regression introduced in 6867e44, affecting 0.2.10–0.2.11:
empty FLASH_ARGS corrupted startup. The fix is limited to argument handling.
New Test-FlashEntry failed before the fix and passed 14 PS7 scenarios with stub
executables for CubeProgrammer/OpenOCD/J-Link afterward. All 17 suites passed
in PS5.1/7 on 2026-10-10; strict specification validation is clean. Local package:
15 source-identical files, SHA-256, 24 help/version calls and unmodified no-argument
CMD startup without HEX all passed. The owner confirmed no-argument startup with
one HEX and CubeProgrammer/ST-Link: programming and verification succeeded in
3.584 s. The agent performed no MCU operations; not published.
Next: signed commit, owner
push, successful CI, land, main CI and v0.2.12 publication; do not move old tags.
The owner closes issue #1 after confirming the result. The release CI gate is deferred.

Published v0.2.11 from 2277d45. Branch, main and tag CI succeeded, including all
16 suites in Windows PowerShell 5.1 and PowerShell 7. Release succeeded; the ZIP
(97,730 bytes), SHA-256 sidecar and bilingual description are present.
The local package was checked separately: 15 files, SHA-256 and 24 RU/EN help/version
calls. Additional manual scenarios are confirmed. An independent download of the
published ZIP failed again on 2026-10-09 due to an environment network error;
GitHub metadata is not a substitute for verifying downloaded bytes.
Directory locking landed on main at 5e2c508 with successful branch/main CI. Owner logs confirm CubeProgrammer/ST-Link
selection, switching to J-Link, cancellation at the first menu preserving settings,
and a second setup rejected with exit 1. No MCU writes. Manual checks of help/info
while locked, cancellation before saving and reopening after release are now confirmed.
Next: commit the release outcome on `codex/release-0.2.11-outcome`, owner push,
successful CI and land. Proposed next stage, not implemented: require successful CI
for the exact tagged commit before building/uploading release assets. Missing,
pending or failed CI should fail closed. The owner still publishes and controls
the description; this gate cannot prevent creation of the release page, which
may remain without assets until a successful rerun.

Completed `codex/directory-lock` stage: agreed and implemented directory locking for working
operations; contenders exit 1, while help/version, DryRun and basic info remain available.
Added TC-37; all 15 suites passed in PS5.1/7 on 2026-10-09, with a clean strict
spec check. Version was 0.2.10 at that stage; no hardware operations were performed.
Setup landed on main at d34347f with successful branch/main CI; implemented
the no-MCU wizard with confirmation, cancellation and early DryRun. Version was
0.2.10. Added TC-36, tests and packaging; all 14 suites passed in PS5.1/7 on
2026-10-09, with a clean strict spec check.
The directory-lock commit is now on main; release preparation is tracked above.

Previous release: v0.2.10 published from c2c9eb7. Branch, main and tag CI and the Release
workflow succeeded. ZIP and SHA-256 assets are attached; RU/EN notes are preserved.
Downloading the published ZIP for independent checksum verification failed due
to an environment network error; the local build was checked separately.
Release notes and workflow landed on main at 0c9349b with successful branch/main CI.
Acceptance results landed at 9c87c24. Specification 1.7 is a draft.
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
Independent verification of the downloaded release ZIP/SHA-256 is still pending.
Directory locking is agreed; tests use two processes without hardware.
Write/erase timeouts, cross-directory probe locking, new engines/profiles and CI-gated releases remain
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
