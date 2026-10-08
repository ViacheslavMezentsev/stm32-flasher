# TODO

## Текущее состояние

- Версия 0.2.9, ветка `codex/inventory-timeouts`. DryRun слит в main (`6867e44`).
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.5.
- CI предыдущей ветки успешен: run 37835926980 для `6867e44`.
- Реализован ранний планировщик DryRun без утилит, USB/MCU, сети, ввода и записи.
  Базовая проверка Intel HEX согласована и добавлена. CMD сохраняет код ошибки
  PowerShell и кавычки в аргументах с пробелами.
- TC-22 выявил зависание чтения stdout/stderr J-Link после выхода процесса;
  добавлен лимит дочитывания 1000 мс. Лимит процесса остаётся 10000 мс.
- Все восемь наборов прошли локально в PS5.1/7 09.10.2026. Новый Test-InventoryTimeout
  автоматически подхватывается CI; текущая ветка ещё не опубликована.
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
- [ ] Проверить и зафиксировать `codex/inventory-timeouts`; затем push владельцем, CI и land.

## Отложено

- Тайм-ауты записи/стирания, блокировки параллельных операций, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Current: version 0.2.9, branch `codex/inventory-timeouts`; DryRun landed on main
at 6867e44 after successful CI run 37835926980. Specification 1.5 is a draft.
Early DryRun planning avoids tools, USB/MCU, network access, prompts and writes.
Basic Intel HEX validation was agreed and implemented; MCU compatibility is not checked.
CMD preserves quoted paths and nonzero exit codes. TC-22 reproduced an unbounded
J-Link output drain after process exit; draining is now limited to 1000 ms.
All eight suites passed locally in PS5.1/7 on 2026-10-09. CI discovers the new suite.
This branch is not pushed, no release is prepared and no hardware operations ran.

Next: review and commit the inventory timeout fix; the owner pushes, checks CI
and decides on land.
Write/erase timeouts, locking, new engines/profiles and CI-gated releases remain
separate follow-ups.
