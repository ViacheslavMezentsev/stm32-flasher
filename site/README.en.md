# GitHub Pages command handbook

[Русский](README.md) | **English**

A static handbook for release 0.3.1. `commands.json` holds RU/EN content for
11 commands; `ci/build_site.py` builds 24 HTML pages using a shared template.
`assets` contains local CSS and the theme selector. Content and navigation
work without JavaScript, a server or external libraries. No MCU tools run.

## Check and preview

From the repository root:

```powershell
python -B -X utf8 ci/test_site.py
python -B -X utf8 ci/build_site.py --output tests/.tmp-pages-preview
Start-Process tests/.tmp-pages-preview/index.html
```

`tests/Test-Pages.ps1` automatically joins regular PS5.1/7 CI. Checks cover
all `bin/*.cmd` entries, RU/EN, routes, local links/anchors, assets, absence of
external scripts and deterministic builds. This is not a browser visual test
or a hardware test.

## Publish

1. The owner selects Settings → Pages → Build and deployment → Source:
   **GitHub Actions**. Repository scripts do not change this setting.
2. A branch push runs regular CI including Test-Pages, without deployment.
3. After successful CI and `git land`, Pages builds and checks the site from
   `main`, deploying only the static output. Manual Pages dispatch from `main`
   is also available. CI/Release workflows and the utility ZIP stay unchanged.
4. URL: https://viacheslavmezentsev.github.io/stm32-flasher/ . Publication is
   not confirmed until the first successful Pages deployment.

When behavior changes, update both languages and the documented version in
the template. Side effects matter more than short routes: normal flashing
does not need erase, check does not resume the core, CubeProgrammer cannot go.
Inspect the index and a long command page on narrow/wide screens, both languages
and themes.
