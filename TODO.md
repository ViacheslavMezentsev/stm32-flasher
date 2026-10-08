# TODO

## Текущее состояние

- Версия 0.2.9, ветка `codex/jlink-failure-regression`. Предыдущая работа слита в main (`f4ec9bd`).
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.3.
- Добавлен шестой набор регрессии: полный PowerShell-процесс при ошибке J-Link.
  Все шесть наборов прошли локально в PS5.1/7 09.10.2026.
  CI подхватывает его автоматически. Удалённый статус CI отдельно не проверялся;
  новый релиз не подготовлен.
- Безопасный DryRun согласован, но полностью не реализован. Текущий DryRun
  нельзя считать гарантией отсутствия обнаружения и файловых изменений.

## Ближайшие шаги

- [x] Согласовать AGENTS и памятки, проверить состав изменений; убрать реальные serial из новых тестов и публикуемых примеров.
- [x] Подготовить подписанные коммиты исправлений, CI и документации.
- [x] Предыдущая ветка опубликована и слита владельцем в main; локально подтверждён `f4ec9bd`.
- [x] Дополнить TC-32 полным запуском с имитацией ошибки J-Link: ненулевой код
  и отсутствие повторной попытки без явного serial.
- [ ] Проверить и зафиксировать `codex/jlink-failure-regression`; затем push владельцем, CI и land.
- [ ] После завершения текущей ветки начать `codex/safe-preview` от актуального main.
- [ ] Согласовать вопрос 9.2.8 ТЗ: глубина проверки Intel HEX для DryRun.
- [ ] Реализовать безопасный DryRun и полные TC-18–TC-19, TC-26–TC-31, TC-34.
- [ ] Проверить зависшие процессы перечисления и пределы ожидания (TC-22).

## Отложено

- Тайм-ауты записи/стирания, блокировки параллельных операций, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Current: version 0.2.9, branch `codex/jlink-failure-regression`; previous work landed on main at f4ec9bd.
USB inventory, J-Link timeout diagnostics and explicit serial selection were fixed.
Specification 1.3 is a draft. A sixth suite covers full PowerShell-process J-Link
failures and is discovered by CI automatically. Remote CI status was not independently
checked. No new release is prepared; full safe DryRun is pending.
All six suites passed locally in PS5.1/7 on 2026-10-09.

Contributor docs are approved and new public fixtures/examples use synthetic serials.
The mocked J-Link failure scenario is complete. Next: review and commit this branch;
the owner pushes, checks CI and decides on land. Start `codex/safe-preview` after
landing current work. Resolve HEX validation scope,
implement safe DryRun and process-timeout tests. Write/erase timeouts, locking,
new engines/profiles and CI-gated releases remain separate follow-ups.
