# Конфигурация запуска / Launch Configuration

## Русский

Начиная с разрабатываемой версии 0.3.0 настройки хранятся в `.flash.json`
в папке вызова, а не рядом с CMD. Версия схемы независима от версии утилиты.
Удобнее изменять настройки через `setup.cmd`.

```json
{
  "schemaVersion": 1,
  "engine": "OPENOCD",
  "probe": "STLINK",
  "stlinkSerial": null,
  "jlinkSerial": null,
  "jlinkDevice": null,
  "openocdTarget": "target/stm32f1x.cfg"
}
```

- `schemaVersion` обязателен и равен целому числу 1. Остальные поля необязательны;
  `null`, пустая строка или отсутствие поля означают отсутствие сохранённого выбора.
- `engine`: `OPENOCD`, `JLINK`, `CUBEPROGRAMMER`, `CUBE` либо абсолютный путь к EXE.
  `probe`: `STLINK` или `JLINK`. Serial хранится строкой, чтобы не потерять ведущие нули.
- Приоритет: явные параметры команды, затем сохранённые значения, затем штатный
  автоматический выбор. Serial берётся для выбранного типа программатора.
- Неизвестные поля, неверные типы, повторяющиеся ключи, комментарии, завершающие
  запятые и неизвестная версия схемы отклоняются. Это не проверка совместимости MCU.

### Переход со старых версий

Без JSON читаются `.flash_engine`, `.probe_type`, `.stlink_serial`, `.jlink_serial`,
`.jlink_device`, `.openocd_target`. Первый рабочий запуск переносит их перед
обнаружением оборудования; setup переносит только после подтверждения сохранения.
Миграция может произойти и перед операцией, которая позже не выполнится, например
из-за отсутствия HEX. Настройки записываются во временный файл, проверяются и
публикуются целиком; старые файлы удаляются только после проверки записанного JSON.

Если запись не удалась, старые настройки сохраняются. Если отказало последующее
удаление старых файлов, запуск прекращается; полный JSON уже сохранён, часть
старых файлов может остаться. При наличии JSON старые файлы всегда игнорируются.
Нет двойной записи в оба формата; старые версии утилиты новый формат не читают.

Help/version не читают настройки. Info и DryRun читают их, но ничего не мигрируют.
Отмена setup не меняет файлы. Повреждённый JSON означает ошибку до обнаружения
оборудования, даже при явно заданных параметрах; автоматического сброса нет.
Для намеренного сброса используйте `flash.cmd -ResetConfig`: он удаляет оба
формата настроек, сохраняя прошивки и историю. `forget.cmd` также удаляет JSON.
Сначала можно посмотреть список удаления с `-DryRun`.

Запись защищена общей блокировкой папки и атомарной заменой существующего файла.
При сбое питания, внешнем редактировании или нестандартной файловой системе
абсолютная сохранность не гарантируется. После аварии может остаться временный
`.flash_config_*.tmp`; он не читается как конфигурация.

## English

For the upcoming 0.3.0 release, settings live in `.flash.json` in the invocation
directory, not beside the CMD files. Its schema version is independent of the
utility version. Prefer `setup.cmd` to edit settings. The example above applies
to both languages.

- `schemaVersion` is required and must be integer 1. Other fields are optional;
  null, an empty string or an omitted field means no saved choice.
- `engine` accepts `OPENOCD`, `JLINK`, `CUBEPROGRAMMER`, `CUBE` or an absolute EXE
  path. `probe` accepts `STLINK` or `JLINK`. Serials are strings, preserving zeros.
- Explicit arguments override saved values, followed by normal automatic
  selection. The saved serial belongs to the selected probe type.
- Unknown fields, invalid types, duplicate keys, comments, trailing commas and
  unsupported schema versions are rejected. MCU compatibility is not validated.

### Migration

Without JSON, the six legacy setting files listed above are read. An operational
run migrates before hardware discovery; setup migrates only after confirmation.
Migration may precede an operation that later fails, for example because no HEX
exists. A temporary file is written, validated and published as a complete JSON;
legacy files are deleted only after validating the published configuration.

A write failure preserves prior settings. If subsequent legacy deletion fails,
the run stops: the complete JSON is already saved, and some legacy files may
remain. Existing JSON always takes precedence; legacy files are ignored.
There is no dual-format write support. Older utility versions cannot read JSON.

Help/version do not read settings. Info and DryRun read but never migrate them.
Cancelling setup leaves files unchanged. Invalid JSON fails before discovery,
even with explicit arguments; there is no automatic reset. An intentional
`flash.cmd -ResetConfig` removes both formats, preserving firmware and history.
`forget.cmd` also removes JSON. Preview cleanup with `-DryRun` first.

Writes use the directory lock and atomic replacement of an existing file.
Power loss, external editors and unusual filesystems are outside the durability
guarantee. A crash may leave `.flash_config_*.tmp`, which is never read as config.
