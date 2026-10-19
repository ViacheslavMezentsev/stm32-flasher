"""Build the bilingual, dependency-free command handbook for GitHub Pages.

Markup and site/assets follow the shared style of the STM32 project sites
(demo-stm32-skills): GitHub Primer colours, dark theme by default, round theme
toggle, boxes, stage/flow/node diagrams, cards and labels.
"""

import argparse
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
REPO = 'https://github.com/ViacheslavMezentsev/stm32-flasher'
FAMILY = 'https://viacheslavmezentsev.github.io/demo-stm32-skills/'
VERSION = '0.3.1'
DOCTOR_BASE = '0.3.0'

# Effect of a command (commands.json "en.effect") -> colour class of the shared style.
KIND = {
    'Inspect': 'offline', 'Configure': 'alt', 'Reads MCU': 'live', 'Core state': 'view',
    'Writes Flash': 'danger', 'Erases Flash': 'danger', 'Deletes files': 'danger',
}

TEXT = {
    'ru': {
        'catalog': 'Команды', 'repo': 'Репозиторий', 'release': 'Скачать выпуск', 'sources': 'Исходники',
        'guide': 'Инструкция', 'sections': 'Разделы', 'home': 'stm32-flasher', 'crumb': 'команды',
        'intro': 'Переносимый набор команд для STM32 через ST-Link и J-Link. От обзора окружения до прошивки и управления ядром.',
        'start_title': 'Быстрый старт',
        'start': 'Все CMD из релизного ZIP положите рядом с прошивкой. Примеры для CMD; в PowerShell добавьте ./ перед именем. Рабочие файлы относятся к папке вызова, не к месту хранения скрипта.',
        'steps': [('info', 'Окружение, версии утилит и USB-программаторы без подключения к MCU.'),
                  ('setup', 'Выбор движка и отладчика после подтверждения, без прошивки платы.'),
                  ('flash', 'Запись и проверка единственного HEX; при нескольких — выбор.')],
        'route': 'Общий маршрут', 'routine': '1. Обновить прошивку',
        'routine_note': 'setup нужен при смене конфигурации; backup — если важно сохранить старое содержимое. flash уже выполняет проверку. Отдельный check — дополнительное сравнение; после него ядро может остаться остановленным.',
        'restore': '2. Сохранить и восстановить',
        'restore_note': 'Сначала backup всей затрагиваемой Flash и check полученной копии. Только после успеха допустим эксперимент или erase. Для восстановления flash получает именно HEX резервной копии, затем check сравнивает его с MCU. Если восстановление не удалось, остановитесь.',
        'control': '3. Управлять выполнением',
        'control_note': 'halt → go продолжает с текущего PC. reset — отдельный путь запуска заново, не обязательный шаг после go. После check: go только для OpenOCD/ST-Link или SEGGER/J-Link; reset — если нужен перезапуск и сочетание движка поддержано.',
        'legend': [('offline', 'осмотр, MCU не трогается'), ('alt', 'настройка'), ('live', 'чтение MCU'),
                   ('view', 'состояние ядра'), ('danger', 'запись, стирание, удаление')],
        'safety': 'До обращения к плате',
        'safety_note': 'Отключите опасные нагрузки. halt не гарантирует остановку периферии и watchdog. Перед записью или стиранием ценных данных нужна проверенная копия. Не запускайте операции с одним отладчиком из разных папок: блокировка действует только внутри папки.',
        'when': 'Когда применять', 'before': 'Перед запуском', 'result': 'Что ожидать',
        'warning': 'Ограничения и последствия', 'example': 'Пример запуска',
        'next': 'Следующий шаг', 'all': 'Все команды', 'context': 'Типовой маршрут',
        'example_note': 'Параметры платы и пути замените на свои. DryRun — только локальный план, не проверка MCU. Обычный запуск выполняет действие.',
        'common': 'Общие правила',
        'rules': [('Справка и версия', '--help и --version есть у всех команд, не читают настройки и не выполняют операций.'),
                  ('Язык', '-Lang ru или -Lang en выбирает язык вывода любой команды.'),
                  ('DryRun', 'Не запускает утилиты, не опрашивает USB/MCU и не меняет файлы. Неполный план завершится ошибкой; код 0 — готовый план, не успех на MCU.'),
                  ('Отчёты', 'Аппаратные операции сохраняют лог, report.html и .history; при ошибке отчёт открывается. info, doctor и setup не являются аппаратными операциями.'),
                  ('Папка вызова', 'Настройки, утилиты, история и резервные копии создаются в папке вызова, даже при запуске CMD по полному пути.'),
                  ('Блокировка', 'Защищает папку от параллельных операций, но не общий отладчик, используемый из разных папок.')],
        'rules_link': 'Общие правила для всех команд',
        'support': 'Движок и состояние ядра',
        'support_note': 'Для check и управления: OpenOCD требует target, SEGGER требует device. Автоопределения модели здесь нет. Неподдерживаемый движок не заменяется автоматически.',
        'source': 'Полная инструкция', 'checked': 'Аппаратные проверки и границы',
        'scope': f'Поведение выпуска {VERSION} · паспорт doctor: {DOCTOR_BASE}',
        'license': 'лицензия MIT', 'family': 'навыки demo-stm32-skills',
        'skip': 'К содержимому', 'engine': 'Движок / отладчик', 'yes': 'Да', 'no': 'Нет',
        'check_note': 'При несовпадении остановитесь и выясните причину: check не исправляет память. При совпадении: go для OpenOCD/ST-Link или SEGGER/J-Link, reset для поддерживаемого перезапуска. CubeProgrammer не выполняет go.',
    },
    'en': {
        'catalog': 'Commands', 'repo': 'Repository', 'release': 'Download release', 'sources': 'Sources',
        'guide': 'Guide (RU)', 'sections': 'Sections', 'home': 'stm32-flasher', 'crumb': 'commands',
        'intro': 'Portable STM32 commands for ST-Link and J-Link. From environment inspection to programming and core control.',
        'start_title': 'Quick start',
        'start': 'Place all CMD files from the release ZIP beside the firmware. Examples use CMD; prefix names with ./ in PowerShell. Working files belong to the calling directory, not the script directory.',
        'steps': [('info', 'Environment, tool versions and USB probes without connecting to the MCU.'),
                  ('setup', 'Choose the engine and probe after confirmation, without programming the board.'),
                  ('flash', 'Program and verify the single HEX; several files offer a choice.')],
        'route': 'Workflow overview', 'routine': '1. Update firmware',
        'routine_note': 'Use setup when configuration changes, and backup if existing contents matter. flash already verifies programming. A separate check is an additional comparison; it may leave the core halted.',
        'restore': '2. Preserve and restore',
        'restore_note': 'First back up all affected Flash and check that copy. Only after success proceed to an experiment or erase. Restore with flash using the backup HEX explicitly, then compare it with the MCU using check. Stop if restoration fails.',
        'control': '3. Control execution',
        'control_note': 'halt → go resumes from the current PC. reset is a separate restart path, not a required step after go. After check: go only for OpenOCD/ST-Link or SEGGER/J-Link; reset when a restart is intended and the engine combination supports it.',
        'legend': [('offline', 'inspection, MCU untouched'), ('alt', 'configuration'), ('live', 'reads the MCU'),
                   ('view', 'core state'), ('danger', 'writes, erases, deletes')],
        'safety': 'Before accessing the board',
        'safety_note': 'Disconnect hazardous loads. halt does not guarantee that peripherals or watchdog stop. Preserve and verify valuable data before writing or erasing. Do not operate on one probe from multiple folders: the lock only protects a single directory.',
        'when': 'When to use', 'before': 'Before running', 'result': 'Expected result',
        'warning': 'Limits and side effects', 'example': 'Example',
        'next': 'Next step', 'all': 'All commands', 'context': 'Typical route',
        'example_note': 'Replace board parameters and paths with your own. DryRun is a local plan, not an MCU test. A normal invocation performs the operation.',
        'common': 'Shared rules',
        'rules': [('Help and version', 'Every command supports --help and --version; they do not read settings or perform operations.'),
                  ('Language', '-Lang ru or -Lang en selects the output language of any command.'),
                  ('DryRun', 'Runs no tools, queries no USB/MCU and changes no files. An incomplete plan fails; exit code 0 means a ready plan, not success on the MCU.'),
                  ('Reports', 'Hardware operations save a log, report.html and .history; errors open the report. info, doctor and setup are not hardware operations.'),
                  ('Calling directory', 'Settings, tools, history and backups are created in the calling directory, even when CMD is started by full path.'),
                  ('Lock', 'Protects a directory from parallel operations, but not a probe shared from several directories.')],
        'rules_link': 'Shared rules for all commands',
        'support': 'Engine and core state',
        'support_note': 'For check and core control, OpenOCD requires a target and SEGGER requires a device. There is no model autodetection here. Unsupported engines are not silently replaced.',
        'source': 'Full guide (RU)', 'checked': 'Hardware evidence and limits (RU)',
        'scope': f'Release {VERSION} behavior · doctor baseline: {DOCTOR_BASE}',
        'license': 'MIT license', 'family': 'demo-stm32-skills',
        'skip': 'Skip to content', 'engine': 'Engine / probe', 'yes': 'Yes', 'no': 'No',
        'check_note': 'Stop and investigate a mismatch: check does not repair memory. After a match: go for OpenOCD/ST-Link or SEGGER/J-Link, or reset for a supported restart. CubeProgrammer cannot go.',
    },
}

CHIP = ('<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">'
        '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="0.5"/>'
        '<path d="M9 2.5v3.5M12 2.5v3.5M15 2.5v3.5M9 18v3.5M12 18v3.5M15 18v3.5M2.5 9h3.5M2.5 12h3.5M2.5 15h3.5M18 9h3.5M18 12h3.5M18 15h3.5"/></svg>')

THEME_ICONS = (
    '<svg class="icon-dark" width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M9.6 1.1a.75.75 0 0 1 .3.9 5.5 5.5 0 0 0 4.1 7.3.75.75 0 0 1 .4 1.3A7 7 0 1 1 8.3 1a.75.75 0 0 1 1.3.1ZM7.4 2.6a5.5 5.5 0 1 0 5.4 8.6 7 7 0 0 1-5.4-8.6Z"/></svg>'
    '<svg class="icon-light" width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 11.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm0 1.5a5 5 0 1 1 0-10 5 5 0 0 1 0 10ZM8 0a.75.75 0 0 1 .75.75v.5a.75.75 0 0 1-1.5 0v-.5A.75.75 0 0 1 8 0Zm0 14a.75.75 0 0 1 .75.75v.5a.75.75 0 0 1-1.5 0v-.5A.75.75 0 0 1 8 14ZM0 8a.75.75 0 0 1 .75-.75h.5a.75.75 0 0 1 0 1.5h-.5A.75.75 0 0 1 0 8Zm14 0a.75.75 0 0 1 .75-.75h.5a.75.75 0 0 1 0 1.5h-.5A.75.75 0 0 1 14 8ZM2.3 2.3a.75.75 0 0 1 1.06 0l.36.36a.75.75 0 0 1-1.06 1.06l-.36-.36a.75.75 0 0 1 0-1.06Zm9.98 9.98a.75.75 0 0 1 1.06 0l.36.36a.75.75 0 0 1-1.06 1.06l-.36-.36a.75.75 0 0 1 0-1.06ZM13.7 2.3a.75.75 0 0 1 0 1.06l-.36.36a.75.75 0 1 1-1.06-1.06l.36-.36a.75.75 0 0 1 1.06 0ZM3.72 12.28a.75.75 0 0 1 0 1.06l-.36.36a.75.75 0 0 1-1.06-1.06l.36-.36a.75.75 0 0 1 1.06 0Z"/></svg>'
    '<svg class="icon-auto" width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0Zm0 1.5v13a6.5 6.5 0 0 0 0-13Z"/></svg>'
)


def esc(value):
    return html.escape(value, quote=True)


def page_name(lang):
    return 'index.en.html' if lang == 'en' else 'index.html'


def kind(command):
    return KIND[command['en']['effect']]


def shell(lang, title, body, command=None):
    t = TEXT[lang]
    prefix = '../../' if command else ''
    home = prefix + page_name(lang)
    assets = prefix + 'assets/'
    ru_current = ' aria-current="page"' if lang == 'ru' else ''
    en_current = ' aria-current="page"' if lang == 'en' else ''
    return f'''<!doctype html>
<html lang="{lang}" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} | stm32-flasher</title>
<meta name="description" content="{esc(title + '. ' + t['intro'])}">
<link rel="stylesheet" href="{assets}site.css">
<script src="{assets}theme.js"></script>
</head>
<body>
<a class="skip" href="#main">{t['skip']}</a>
<header class="site-header">
  <div class="inner">
    <a class="brand" href="{home}">{CHIP}<span>stm32-flasher</span></a>
    <nav class="site-nav" aria-label="{t['sections']}">
      <a href="{home}#commands">{t['catalog']}</a>
      <a class="wide" href="{REPO}">{t['repo']}</a>
      <span class="lang-switch"><a href="index.html" lang="ru" hreflang="ru"{ru_current}>RU</a><a href="index.en.html" lang="en" hreflang="en"{en_current}>EN</a></span>
      <button id="theme-toggle" class="theme-toggle" type="button" aria-label="Theme">{THEME_ICONS}</button>
    </nav>
  </div>
</header>
<main id="main">
{body}
</main>
<footer class="site-footer">
  <div class="inner">
    <span>stm32-flasher · {t['license']} · {t['scope']}</span>
    <a href="{REPO}">{t['sources']}</a>
    <a href="{REPO}/blob/v{VERSION}/docs/user-guide.md">{t['source']}</a>
    <a href="{REPO}/blob/v{VERSION}/docs/testing.md">{t['checked']}</a>
    <a href="{FAMILY}">{t['family']}</a>
  </div>
</footer>
</body>
</html>
'''


def node(command, lang, prefix='', active=None):
    name = command['name']
    title = esc(command[lang]['title'])
    if name == active:
        return f'<div class="node {kind(command)} current" aria-current="page"><h3><code>{name}</code></h3><p>{title}</p></div>'
    return f'<a class="node {kind(command)}" href="{prefix}commands/{name}/{page_name(lang)}"><h3><code>{name}</code></h3><p>{title}</p></a>'


def flow(names, index, lang, prefix='', active=None):
    parts = []
    for position, name in enumerate(names):
        if position:
            parts.append('<div class="arrow"></div>')
        parts.append(node(index[name], lang, prefix, active))
    return '<div class="flow">' + ''.join(parts) + '</div>'


def legend(lang):
    return '<div class="legend">' + ''.join(f'<span class="{c}">{esc(text)}</span>' for c, text in TEXT[lang]['legend']) + '</div>'


def stage(title, note, names, index, lang):
    return (f'<div class="stage plain"><div class="stage-title">{title}</div>'
            f'<div class="stage-note">{note}</div>{flow(names, index, lang)}</div>')


def support(lang):
    t = TEXT[lang]
    rows = [('OpenOCD / ST-Link', 'yes', 'yes', 'yes'), ('SEGGER / J-Link', 'yes', 'yes', 'yes'),
            ('CubeProgrammer / ST-Link', 'yes', 'no', 'yes'), ('CubeProgrammer / J-Link', 'no', 'no', 'no')]
    table = ''.join('<tr><th scope="row">' + row[0] + '</th>' + ''.join(
        f'<td class="{v}">{t[v]}</td>' for v in row[1:]) + '</tr>' for row in rows)
    return (f'<div class="box"><h2 id="support">{t["support"]}</h2><p>{t["support_note"]}</p>'
            f'<div class="table-wrap"><table><thead><tr><th>{t["engine"]}</th><th>halt</th><th>go</th><th>reset</th></tr></thead>'
            f'<tbody>{table}</tbody></table></div></div>')


def rules(lang):
    t = TEXT[lang]
    facts = ''.join(f'<div class="fact"><b>{esc(b)}</b>{esc(text)}</div>' for b, text in t['rules'])
    return f'<div class="box"><h2 id="rules">{t["common"]}</h2><div class="facts">{facts}</div></div>'


def index_page(commands, index, lang):
    t = TEXT[lang]
    suffix = page_name(lang)
    chips = ''.join(f'<span class="label">{x}</span>' for x in ('Windows 10/11', 'PowerShell 5.1 / 7', 'ST-Link', 'J-Link'))
    chips += f'<span class="label" style="--c: var(--success)">{VERSION}</span>'
    steps = ''.join(f'<div class="step"><b><code>{n}.cmd</code></b>{esc(text)}</div>' for n, text in t['steps'])
    cards = ''.join(
        f'<a class="card" href="commands/{c["name"]}/{suffix}"><h3><code>{c["name"]}.cmd</code></h3>'
        f'<p>{esc(c[lang]["title"])}. {esc(c[lang]["when"])}</p>'
        f'<div class="meta"><span class="label {kind(c)}">{esc(c[lang]["effect"])}</span></div></a>' for c in commands)
    body = f'<h1>stm32-flasher</h1>\n<p class="lead">{t["intro"]}</p>\n<div class="chips">{chips}</div>\n'
    body += (f'<div class="actions"><a class="btn primary" href="{REPO}/releases/tag/v{VERSION}">{t["release"]} {VERSION}</a>'
             f'<a class="btn" href="{REPO}">{t["sources"]}</a><a class="btn" href="{REPO}/blob/v{VERSION}/docs/user-guide.md">{t["guide"]}</a></div>\n')
    body += f'<div class="box"><h2 id="start">{t["start_title"]}</h2><p>{t["start"]}</p><div class="cycle">{steps}</div></div>\n'
    body += f'<div class="box"><h2 id="route">{t["route"]}</h2>{legend(lang)}'
    body += stage(t['routine'], t['routine_note'], ['info', 'doctor', 'setup', 'flash', 'check'], index, lang)
    body += stage(t['restore'], t['restore_note'], ['backup', 'check', 'erase', 'flash', 'check'], index, lang)
    body += stage(t['control'], t['control_note'], ['halt', 'go'], index, lang) + '</div>\n'
    body += f'<div class="callout view"><h2 id="safety">{t["safety"]}</h2><p>{t["safety_note"]}</p></div>\n'
    body += f'<div class="box"><h2 id="commands">{t["all"]}</h2><div class="cards">{cards}</div></div>\n'
    body += support(lang) + '\n' + rules(lang)
    return shell(lang, t['catalog'], body)


def command_page(c, index, lang):
    t = TEXT[lang]
    d = c[lang]
    suffix = page_name(lang)
    name = c['name']
    body = (f'<div class="breadcrumb"><a href="../../{suffix}">{t["home"]}</a> / '
            f'<a href="../../{suffix}#commands">{t["crumb"]}</a> / {name}</div>\n')
    body += f'<h1>{name}.cmd</h1>\n<p class="lead">{esc(d["title"])}</p>\n'
    body += f'<div class="chips"><span class="label {kind(c)}">{esc(d["effect"])}</span></div>\n'
    body += f'<div class="box"><h2 id="route">{t["context"]}</h2>{flow(c["route"], index, lang, "../../", name)}</div>\n'
    about = ''.join(f'<h3 id="{key}">{t[key]}</h3><p>{esc(d[key])}</p>' for key in ('when', 'before', 'result'))
    example = (f'<h2 id="example">{t["example"]}</h2><p class="muted">{t["example_note"]}</p>'
               f'<pre><code>{esc(c["example"])}</code></pre><p><code>{name}.cmd --help</code></p>')
    body += f'<div class="cols"><div class="box">{about}</div><div class="box">{example}</div></div>\n'
    callout = 'danger' if kind(c) == 'danger' else 'view'
    body += f'<div class="callout {callout}"><h2 id="warning">{t["warning"]}</h2><p>{esc(d["warning"])}</p></div>\n'
    if name in ('halt', 'go', 'reset', 'check'):
        body += support(lang) + '\n'
    if name == 'check':
        body += f'<div class="box"><p>{t["check_note"]}</p><a class="btn" href="../reset/{suffix}">reset.cmd →</a></div>\n'
    body += (f'<div class="box"><h2 id="next">{t["next"]}</h2><div class="actions">'
             f'<a class="btn primary" href="../{c["next"]}/{suffix}">{c["next"]}.cmd →</a>'
             f'<a class="btn" href="../../{suffix}#rules">{t["rules_link"]}</a></div></div>')
    return shell(lang, name + ' — ' + d['title'], body, name)


def build(destination):
    commands = json.loads((ROOT / 'site/commands.json').read_text(encoding='utf-8'))
    index = {c['name']: c for c in commands}
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'site/assets', destination / 'assets', dirs_exist_ok=True)
    for lang in TEXT:
        suffix = page_name(lang)
        (destination / suffix).write_text(index_page(commands, index, lang), encoding='utf-8', newline='\n')
        for c in commands:
            directory = destination / 'commands' / c['name']
            directory.mkdir(parents=True, exist_ok=True)
            (directory / suffix).write_text(command_page(c, index, lang), encoding='utf-8', newline='\n')
    (destination / '.nojekyll').touch()
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.output.resolve())
