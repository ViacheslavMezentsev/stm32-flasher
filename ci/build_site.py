"""Build the bilingual, dependency-free command handbook for GitHub Pages."""

import argparse
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
REPO = 'https://github.com/ViacheslavMezentsev/stm32-flasher'
TEXT = {
    'ru': {
        'catalog': 'Команды', 'repo': 'Репозиторий', 'release': 'Скачать выпуск',
        'intro': 'Переносимый набор команд для STM32 через ST-Link и J-Link. От обзора окружения до прошивки и управления ядром.',
        'start': 'Все CMD из релизного ZIP положите рядом с прошивкой. Примеры для CMD; в PowerShell добавьте ./ перед именем. Рабочие файлы относятся к папке вызова, не к месту хранения скрипта.',
        'route': 'Общий маршрут', 'routine': '01 / Обновить прошивку',
        'routine_note': 'setup нужен при смене конфигурации; backup — если важно сохранить старое содержимое. flash уже выполняет проверку. Отдельный check — дополнительное сравнение; после него ядро может остаться остановленным.',
        'restore': '02 / Сохранить и восстановить',
        'restore_note': 'Сначала backup всей затрагиваемой Flash и check полученной копии. Только после успеха допустим эксперимент или erase. Для восстановления flash получает именно HEX резервной копии, затем check сравнивает его с MCU. Если восстановление не удалось, остановитесь.',
        'control': '03 / Управлять выполнением',
        'control_note': 'halt → go продолжает с текущего PC. reset — отдельный путь запуска заново, не обязательный шаг после go. После check: go только для OpenOCD/ST-Link или SEGGER/J-Link; reset — если нужен перезапуск и сочетание движка поддержано.',
        'safety': 'До обращения к плате',
        'safety_note': 'Отключите опасные нагрузки. halt не гарантирует остановку периферии и watchdog. Перед записью или стиранием ценных данных нужна проверенная копия. Не запускайте операции с одним отладчиком из разных папок: блокировка действует только внутри папки.',
        'when': 'Когда применять', 'before': 'Перед запуском', 'result': 'Что ожидать',
        'warning': 'Ограничения и последствия', 'example': 'Пример запуска',
        'next': 'Следующий шаг', 'all': 'Все команды', 'context': 'Типовой маршрут',
        'example_note': 'Параметры платы и пути замените на свои. DryRun — только локальный план, не проверка MCU. Обычный запуск выполняет действие.',
        'common': 'Общие правила',
        'common_note': 'У всех команд: --help, --version, -Lang ru|en и -DryRun. Справка и версия не читают настройки и не выполняют операций. DryRun не запускает утилиты, не опрашивает USB/MCU и не меняет файлы. Неполный план завершится ошибкой. Рабочие аппаратные операции сохраняют лог, report.html и .history; при ошибке отчёт открывается. info, doctor и setup не являются аппаратными операциями.',
        'support': 'Движок и состояние ядра',
        'support_note': 'Для check и управления: OpenOCD требует target, SEGGER требует device. Автоопределения модели здесь нет. Неподдерживаемый движок не заменяется автоматически.',
        'source': 'Полная инструкция', 'checked': 'Аппаратные проверки и границы',
        'scope': 'Поведение выпуска 0.3.1 · паспорт doctor: 0.3.0',
        'theme': 'Тема', 'auto': 'Системная', 'light': 'Светлая', 'dark': 'Тёмная',
        'skip': 'К содержимому', 'engine': 'Движок / отладчик',
    },
    'en': {
        'catalog': 'Commands', 'repo': 'Repository', 'release': 'Download release',
        'intro': 'Portable STM32 commands for ST-Link and J-Link. From environment inspection to programming and core control.',
        'start': 'Place all CMD files from the release ZIP beside the firmware. Examples use CMD; prefix names with ./ in PowerShell. Working files belong to the calling directory, not the script directory.',
        'route': 'Workflow overview', 'routine': '01 / Update firmware',
        'routine_note': 'Use setup when configuration changes, and backup if existing contents matter. flash already verifies programming. A separate check is an additional comparison; it may leave the core halted.',
        'restore': '02 / Preserve and restore',
        'restore_note': 'First back up all affected Flash and check that copy. Only after success proceed to an experiment or erase. Restore with flash using the backup HEX explicitly, then compare it with the MCU using check. Stop if restoration fails.',
        'control': '03 / Control execution',
        'control_note': 'halt → go resumes from the current PC. reset is a separate restart path, not a required step after go. After check: go only for OpenOCD/ST-Link or SEGGER/J-Link; reset when a restart is intended and the engine combination supports it.',
        'safety': 'Before accessing the board',
        'safety_note': 'Disconnect hazardous loads. halt does not guarantee that peripherals or watchdog stop. Preserve and verify valuable data before writing or erasing. Do not operate on one probe from multiple folders: the lock only protects a single directory.',
        'when': 'When to use', 'before': 'Before running', 'result': 'Expected result',
        'warning': 'Limits and side effects', 'example': 'Example',
        'next': 'Next step', 'all': 'All commands', 'context': 'Typical route',
        'example_note': 'Replace board parameters and paths with your own. DryRun is a local plan, not an MCU test. A normal invocation performs the operation.',
        'common': 'Shared rules',
        'common_note': 'Every command supports --help, --version, -Lang ru|en and -DryRun. Help/version do not read settings or perform operations. DryRun runs no tools, queries no USB/MCU and changes no files. An incomplete plan fails. Hardware operations save a log, report.html and .history; errors open the report. info, doctor and setup are not hardware operations.',
        'support': 'Engine and core state',
        'support_note': 'For check and core control, OpenOCD requires a target and SEGGER requires a device. There is no model autodetection here. Unsupported engines are not silently replaced.',
        'source': 'Full guide (RU)', 'checked': 'Hardware evidence and limits (RU)',
        'scope': 'Release 0.3.1 behavior · doctor baseline: 0.3.0',
        'theme': 'Theme', 'auto': 'System', 'light': 'Light', 'dark': 'Dark',
        'skip': 'Skip to content', 'engine': 'Engine / probe',
    },
}


def esc(value):
    return html.escape(value, quote=True)


def shell(lang, title, body, command=None):
    t = TEXT[lang]
    prefix = '../../' if command else ''
    suffix = 'index.en.html' if lang == 'en' else 'index.html'
    assets = prefix + 'assets/'
    options = ''.join(f'<option value="{key}">{t[key]}</option>' for key in ('auto', 'light', 'dark'))
    return f'''<!doctype html>
<html lang="{lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} | stm32-flasher</title>
<meta name="description" content="{esc(title + '. ' + t['intro'])}">
<link rel="stylesheet" href="{assets}site.css"><script defer src="{assets}theme.js"></script></head>
<body><a class="skip" href="#main">{t['skip']}</a>
<header><div class="header-inner"><a class="brand" href="{prefix}{suffix}">stm32-flasher</a>
<nav aria-label="{t['catalog']}"><a href="{prefix}{suffix}#commands">{t['catalog']}</a>
<a href="{REPO}">GitHub</a><a href="index.html" lang="ru" hreflang="ru" {'aria-current="page"' if lang == 'ru' else ''}>Русский</a>
<span aria-hidden="true">|</span><a href="index.en.html" lang="en" hreflang="en" {'aria-current="page"' if lang == 'en' else ''}>English</a>
<label class="theme"><span class="sr-only">{t['theme']}</span><select id="theme" aria-label="{t['theme']}">{options}</select></label></nav></div></header>
<main id="main">{body}</main><footer><span>{t['scope']}</span>
<a href="{REPO}/blob/v0.3.1/docs/user-guide.md">{t['source']}</a>
<a href="{REPO}/blob/v0.3.1/docs/testing.md">{t['checked']}</a></footer></body></html>
'''


def flow(names, lang, prefix='', active=None):
    suffix = 'index.en.html' if lang == 'en' else 'index.html'
    items = []
    for name in names:
        current = 'aria-current="page"' if name == active else ''
        items.append(f'<li><a {current} href="{prefix}commands/{name}/{suffix}"><code>{name}</code></a></li>')
    return '<ol class="flow">' + ''.join(items) + '</ol>'


def support(lang):
    t = TEXT[lang]
    rows = [('OpenOCD / ST-Link', 'yes', 'yes', 'yes'), ('SEGGER / J-Link', 'yes', 'yes', 'yes'),
            ('CubeProgrammer / ST-Link', 'yes', 'no', 'yes'), ('CubeProgrammer / J-Link', 'no', 'no', 'no')]
    labels = {'yes': 'Да' if lang == 'ru' else 'Yes', 'no': 'Нет' if lang == 'ru' else 'No'}
    table = ''.join('<tr><th scope="row">' + row[0] + '</th>' + ''.join(
        f'<td class="{v}">{labels[v]}</td>' for v in row[1:]) + '</tr>' for row in rows)
    return f'<section><h2>{t["support"]}</h2><p>{t["support_note"]}</p><div class="table-wrap"><table><thead><tr><th>{t["engine"]}</th><th>halt</th><th>go</th><th>reset</th></tr></thead><tbody>{table}</tbody></table></div></section>'


def build(destination):
    commands = json.loads((ROOT / 'site/commands.json').read_text(encoding='utf-8'))
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'site/assets', destination / 'assets', dirs_exist_ok=True)
    for lang, t in TEXT.items():
        suffix = 'index.en.html' if lang == 'en' else 'index.html'
        cards = ''.join(f'<a class="card" href="commands/{c["name"]}/{suffix}"><span class="effect">{esc(c[lang]["effect"])}</span><h3>{c["name"]}.cmd</h3><p>{esc(c[lang]["title"])}</p></a>' for c in commands)
        body = f'<p class="eyebrow">Windows · STM32 · ST-Link / J-Link</p><h1>stm32-flasher</h1><p class="lead">{t["intro"]}</p><a href="{REPO}/releases/tag/v0.3.1">{t["release"]} 0.3.1 →</a><p class="start">{t["start"]}</p>'
        body += f'<section><h2>{t["route"]}</h2><h3>{t["routine"]}</h3>{flow(["info", "doctor", "setup", "flash", "check"], lang)}<p>{t["routine_note"]}</p>'
        body += f'<h3>{t["restore"]}</h3>{flow(["backup", "check", "erase", "flash", "check"], lang)}<p>{t["restore_note"]}</p>'
        body += f'<h3>{t["control"]}</h3>{flow(["halt", "go"], lang)}<p>{t["control_note"]}</p></section>'
        body += f'<aside class="warning"><h2>{t["safety"]}</h2><p>{t["safety_note"]}</p></aside><section id="commands"><h2>{t["all"]}</h2><div class="cards">{cards}</div></section>'
        body += support(lang) + f'<section><h2>{t["common"]}</h2><p>{t["common_note"]}</p></section>'
        (destination / suffix).write_text(shell(lang, t['catalog'], body), encoding='utf-8')
        for c in commands:
            d = c[lang]
            body = f'<a href="../../{suffix}#commands">← {t["all"]}</a><p class="eyebrow">{esc(d["effect"])}</p><h1>{c["name"]}.cmd</h1><p class="lead">{esc(d["title"])}</p>'
            body += f'<section><h2>{t["context"]}</h2>{flow(c["route"], lang, "../../", c["name"])}</section><div class="detail">'
            body += '<article>' + ''.join(f'<section id="{key}"><h2>{t[key]}</h2><p>{esc(d[key])}</p></section>' for key in ('when', 'before', 'result'))
            body += f'<section id="example"><h2>{t["example"]}</h2><p>{t["example_note"]}</p><pre><code>{esc(c["example"])}</code></pre><p><code>{c["name"]}.cmd --help</code></p></section></article>'
            body += f'<aside class="warning"><h2>{t["warning"]}</h2><p>{esc(d["warning"])}</p></aside></div>'
            if c['name'] in ('halt', 'go', 'reset', 'check'):
                body += support(lang)
            if c['name'] == 'check':
                note = ('При несовпадении остановитесь и выясните причину: check не исправляет память. При совпадении: go для OpenOCD/ST-Link или SEGGER/J-Link, reset для поддерживаемого перезапуска. CubeProgrammer не выполняет go.' if lang == 'ru' else
                        'Stop and investigate a mismatch: check does not repair memory. After a match: go for OpenOCD/ST-Link or SEGGER/J-Link, or reset for a supported restart. CubeProgrammer cannot go.')
                body += f'<p>{note}</p><a href="../reset/{suffix}">reset.cmd →</a>'
            body += f'<section><h2>{t["next"]}</h2><a href="../{c["next"]}/{suffix}">{c["next"]}.cmd →</a><p>{t["common_note"]}</p></section>'
            directory = destination / 'commands' / c['name']
            directory.mkdir(parents=True, exist_ok=True)
            (directory / suffix).write_text(shell(lang, c['name'] + ' — ' + d['title'], body, c['name']), encoding='utf-8')
    (destination / '.nojekyll').touch()
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.output.resolve())
