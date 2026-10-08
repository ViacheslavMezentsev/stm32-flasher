# TODO

## Текущее состояние

- Версия 0.2.9, ветка `codex/info-probe-serials`; изменения подготовлены к публикации ветки.
- Уточнены USB-перечисление ST-Link, тайм-аут J-Link и выбор по явному serial.
- Документация находится в `docs`; ТЗ — черновик ревизии 1.3.
- Пять наборов регрессии прошли локально в PS5.1/7; обновлённый CI на GitHub
  ещё не проверен после push. Новый релиз не подготовлен.
- Безопасный DryRun согласован, но полностью не реализован. Текущий DryRun
  нельзя считать гарантией отсутствия обнаружения и файловых изменений.

## Ближайшие шаги

- [x] Согласовать AGENTS и памятки, проверить состав изменений; убрать реальные serial из новых тестов и публикуемых примеров.
- [x] Подготовить подписанные коммиты исправлений, CI и документации.
- [ ] Владелец делает push рабочей ветки, проверяет CI и решает о `git land`.
- [ ] Дополнить TC-32 полным запуском с имитацией ошибки J-Link: ненулевой код
  и отсутствие повторной попытки без явного serial.
- [ ] После завершения текущей ветки начать `codex/safe-preview` от актуального main.
- [ ] Согласовать вопрос 9.2.8 ТЗ: глубина проверки Intel HEX для DryRun.
- [ ] Реализовать безопасный DryRun и полные TC-18–TC-19, TC-26–TC-31, TC-34.
- [ ] Проверить зависшие процессы перечисления и пределы ожидания (TC-22).

## Отложено

- Тайм-ауты записи/стирания, блокировки параллельных операций, профили и новые
  движки требуют отдельного согласования.
- Связать публикацию релиза с успешным CI; пока release workflow независим.

## English

Current: version 0.2.9, branch `codex/info-probe-serials`, changes prepared for branch publication.
USB inventory, J-Link timeout diagnostics and explicit serial selection were fixed.
Specification 1.3 is a draft. Five suites passed locally in PS5.1/7; the updated
GitHub CI has not run yet. No new release is prepared; full safe DryRun is pending.

Contributor docs are approved and new public fixtures/examples use synthetic serials.
Signed commits are prepared. Next: the owner pushes the branch,
checks CI and decides on land. Add the full mocked J-Link failure scenario, then
start `codex/safe-preview` after landing current work. Resolve HEX validation scope,
implement safe DryRun and process-timeout tests. Write/erase timeouts, locking,
new engines/profiles and CI-gated releases remain separate follow-ups.
