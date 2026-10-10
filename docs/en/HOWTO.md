# HOWTO

[Русский](../ru/HOWTO.md). PowerShell examples start at the clone root unless noted.
Examples do not authorize an agent to push or operate hardware.

## Compare MCU memory

In the firmware directory: `check.cmd -DryRun`, then `check.cmd` to read and compare.
Equivalent: `flash.cmd -Command check -HexFile firmware.hex`.
Use `./check.cmd` in PowerShell or simply `check` in CMD.
The name avoids the built-in CMD `verify` command.
Specify `-HexFile` when several images exist. Engine/probe settings come from
`.flash.json`; explicit options take precedence. OpenOCD requires a saved target
or `-Target target/stm32f1x.cfg`; J-Link requires a device.
The core may remain halted. There is no implicit programming, erase, reset or resume.
Only HEX data bytes are compared, not the entire Flash. Board-specific behavior
still needs hardware validation; halting a power-control device may also be unsafe.

## Core control

Start with `halt.cmd -DryRun` in the project directory. Actual operations:
`halt.cmd` halts the core, `go.cmd` resumes without reset, and `reset.cmd`
resets the MCU and runs. Reset does not clear configuration.
Equivalent: `flash.cmd -Command halt` (or go/reset). No HEX is needed or read.
Settings come from `.flash.json`; explicit options take precedence. Without a
pinned serial, multiple probes trigger a menu; a single probe needs no serial.

OpenOCD/ST-Link requires a saved or explicit `-Target`; SEGGER/J-Link requires
`-Device`. CubeProgrammer/ST-Link supports halt/reset; go and CubeProgrammer/J-Link
are currently rejected without switching engines. For J-Link, explicitly select
`-Engine JLINK` or use setup. Success reflects the tool's state response at the
time of the check, not application health. Peripherals/watchdogs may keep running
while halted. Even halting a power-control board may be unsafe; agree on a safe
hardware test setup first.

## Localization checks

Test the no-argument entry separately with
`pwsh -NoProfile -File tests/Test-FlashEntry.ps1` (or Windows PowerShell).
It runs real CMD/EXE processes with stubs for three engines, without MCU access.
Do not substitute a call with `-Lang` or `-HexFile`: nonempty arguments concealed
issue #1 in 0.2.10–0.2.11. Version 0.2.12 fixes it; replace flash.cmd without
clearing project settings.

Without hardware: `pwsh -NoProfile -File tests/Test-Localization.ps1`.
For Windows PowerShell, run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Localization.ps1`.
This checks the main dictionaries, placeholder indices and literal T keys;
Test-Help checks RU/EN help. Set language on each invocation (`info.cmd -Lang en`);
it is not persisted. PowerShell variables such as `$repo` must be set separately
in each terminal window.

## Unified configuration

See [the .flash.json format and legacy migration](../reference/launch-configuration.md#english).
Preview with `info.cmd` or `setup.cmd -DryRun`; neither migrates settings.
`setup.cmd` saves JSON only after confirmation. Fix invalid JSON before proceeding;
an intentional reset is `flash.cmd -ResetConfig`. Preview deletion with
`flash.cmd -ResetConfig -DryRun`.

## Git workflow without PRs


Inspect existing work first:

```powershell
git status --short --branch
git diff --stat
git diff --check
```

Start new work only with a clean tree after completing the current branch:

```powershell
git fetch origin
git switch main
git merge --ff-only origin/main
git switch -c codex/task-name
```

After testing, stage explicit files, review and sign:

```powershell
git add -- AGENTS.md TODO.md docs/ru/maintenance.md docs/en/maintenance.md
git diff --cached
git commit -S -m "docs: document contributor workflow"
```

This file list is illustrative, not the complete current change. Inspect signing
without changing configuration:

```powershell
git config --get commit.gpgsign
git config --get gpg.format
git config --get user.signingkey
```

The owner pushes the branch, checks CI for that exact commit and lands with a clean tree:

```powershell
$branch = git branch --show-current
git push -u origin $branch
# Wait for successful CI and review the diff and commits.
git config --get alias.land
git land $branch
```

`git land` is a local alias, not a Git built-in. The inspected alias fetches,
switches to main, fast-forwards origin/main and the work branch, runs
`git push --atomic origin main :<branch>`, then deletes the local branch.
It neither runs tests nor waits for CI. Never pass main as the work branch.
Stop if the alias is missing/different or history diverges; do not install blindly
or force-push. Signing failures must not be bypassed.

## Automated checks

Test inventory timeouts without hardware (TC-22):

```powershell
pwsh -NoProfile -File tests/Test-InventoryTimeout.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-InventoryTimeout.ps1
```

The test compiles a temporary EXE using built-in Windows PowerShell/.NET Framework;
no extra SDK is needed. It covers a hung process and inherited stdout/stderr pipes,
including each pipe separately. Enumeration timeouts do not limit flashing or the
total duration of `info.cmd`.

If a push produces no jobs, open Actions, the run, then Annotations. An
`Invalid workflow file` error happens before a Windows runner is assigned;
local test runs cannot detect it. Use a literal `shell: pwsh` and pass the matrix
value through `env` to `Invoke-Tests.ps1 -PowerShellExe`. Parsing YAML alone does
not validate GitHub Actions expression contexts.

Reproduce J-Link failure without hardware or installed engines:

```powershell
pwsh -NoProfile -File tests/Test-JLinkFailure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-JLinkFailure.ps1
```

A temporary copy mocks external calls; the working flash.cmd is unchanged.
A mutation control deliberately disables the serial-free retry guard.

Full suite:

```powershell
pwsh -NoProfile -File tests/Invoke-Tests.ps1 -LogDirectory tests/.tmp-ci-logs-pwsh
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1 -LogDirectory tests/.tmp-ci-logs-ps51
python -X utf8 tests/tools/check_spec.py docs/TECHNICAL_SPECIFICATION.md --strict
```

Logs and results.json are stored in those directories; GitHub uploads job artifacts.
The runner streams lines as they arrive and prints PASS/FAIL, elapsed seconds and
exit code after each suite. JSON includes `DurationSeconds`. A test can remain
silent while waiting for a timeout. Check the Actions job state before restarting
solely because output has paused.
CI does not validate physical SWD, reset or board restoration. Release publishing
is not yet automatically gated by CI. See [testing](../testing.md), in Russian.

## Workspace and inventory

```powershell
New-Item -ItemType Directory -Force tests/manual/01-probe-inventory
Set-Location tests/manual/01-probe-inventory
$tool = (Resolve-Path ../../../bin).Path
# Invoke from here or copy the commands beside firmware:
# Copy-Item "$tool/*.cmd" $firmwareDirectory
# The invocation directory owns settings and history.
& "$tool/info.cmd" --help
& "$tool/flash.cmd" --version
& "$tool/info.cmd"
```

Info enumerates USB; ProbeTarget connects to the MCU. For J-Link timeouts, check
the USB hub and power, then retry inventory. A timeout alone does not prove an MCU
fault. A Windows instance ID such as `7&...` is not a probe serial.

## SHA-256 and explicit flashing

In the directory containing your mcu_lts_board.hex:

```powershell
$file = Get-Item .\mcu_lts_board.hex
$hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($file.FullName + '.sha256') -Encoding ASCII -Value "$hash *$($file.Name)"
```

This records the current file hash, not trusted provenance. The following commands
write MCU memory. First back up all affected memory for experiments; enter a serial
from fresh inventory and choose only the command matching your board and probe:

```powershell
$serial = Read-Host 'Selected probe serial'
& "$tool/flash.cmd" -HexFile .\mcu_lts_board.hex -Engine OPENOCD -Probe STLINK -Serial $serial -Target target/stm32g4x.cfg
# Alternative for a confirmed STM32G431CB with J-Link:
& "$tool/flash.cmd" -HexFile .\mcu_lts_board.hex -Engine JLINK -Serial $serial -Device STM32G431CB
```

Do not run both indiscriminately. Firmware and MCU must match; an explicit serial
is not replaced by another probe.

## BluePill backup and restoration

Only for a confirmed STM32F103C8 with 64 KiB user Flash and J-Link:

```powershell
& "$tool/backup.cmd" -Engine JLINK -Serial $serial -Device STM32F103C8 -Size 65536 -Output backups/before.hex
```

Before erasing, verify successful reading, full range and SHA-256; preferably
compare bytes from a second read. Preserve the copy and logs outside the experiment.
Do not erase protected memory or use an unconfirmed size. After separate authorization:

```powershell
& "$tool/erase.cmd" -Engine JLINK -Serial $serial -Device STM32F103C8
```

Restore after the experiment, including a failed experiment:

```powershell
& "$tool/flash.cmd" -HexFile backups/before.hex -Engine JLINK -Serial $serial -Device STM32F103C8
```

Check verification, read back and compare bytes, and separately check application
startup. Stop and report to the owner if restoration fails.

## Cleanup of the calling directory

```powershell
& "$tool/forget.cmd" -DryRun
& "$tool/flash.cmd" -ResetConfig
# If logs, reports and downloaded tools should also be removed:
& "$tool/forget.cmd"
```

The first call previews deletion, the second removes settings, the last removes
generated artifacts while preserving backups and firmware inputs. Check the current
directory first.

`Linked cleanup path/content` means a link was found in a cleanup path. Do not
delete its target just to proceed. Inspect the directory layout, then rerun DryRun.
An error does not roll back earlier deletions; do not change links concurrently
with cleanup. Regression in a temporary fixture without user data:

```powershell
pwsh -NoProfile -File tests/Test-CleanupSafety.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-CleanupSafety.ps1
```

## Check Reports Without Hardware

```powershell
pwsh -NoProfile -File tests/Test-ReportHistory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-ReportHistory.ps1
pwsh -NoProfile -File tests/Test-HistoryRetention.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-HistoryRetention.ps1
```

The test mocks CubeProgrammer, checks RU/EN flash/erase/backup reports and
intercepts browser opening. No MCU or installed probe tools are used.
Artifacts are created in a temporary fixture under tests and removed afterwards.
This does not verify hardware behavior or HTML rendering in a browser.

History: limiting the index to 20 rows does not delete older files.
An archive suffix `_1`, `_2` indicates an occupied name, not a retried MCU operation.
New archived reports link to the adjacent `index.html`; old reports are not migrated.
Run operations sequentially: suffixes do not replace process locking.

## Reconfiguration

Run `setup.cmd` from the project directory. Select an engine, probe type/device,
then optional OpenOCD target or J-Link device. Confirm the summary with `y`.
`q` or empty menu input cancels; an empty target/device defers detection/prompting
until an operation. Empty confirmation cancels.

"STLINK | Auto" and "JLINK | Auto" save the type without a serial. Saving replaces
all six settings, clearing stale serials and unused target/device values.
Previous values are displayed first; re-enter a target/device to keep it.
Multiple devices of the selected type require selection at the next operation.
USB labels are displayed; MCU model and firmware compatibility are not detected or checked.
OpenOCD can be selected before installation; any download happens during an operation.

`setup.cmd -DryRun` shows saved settings and the wizard plan without prompts,
USB discovery, tools, network access or writes. `--help`/`--version` work as usual.
The wizard is interactive; engine/probe overrides and `-Silent` are rejected.
Firmware, backups, history, reports and tools are preserved. Cancellation exits 0;
invalid input/save failure exits 1. Handled write failures roll back settings;
this does not protect against process termination or power loss.

## Concurrent Runs

Flash/erase/backup/setup/forget/ResetConfig and `info -ProbeTarget` hold the directory
until completion. A second run immediately exits 1 with a busy message before
changing files or accessing hardware. Another directory is independent.
`--help`, `--version`, every `-DryRun` and basic `info` remain available;
basic info may observe settings while they are being saved.

Manual check without MCU access: leave `setup.cmd` at its first menu in one terminal.
In another terminal in the same directory, run `setup.cmd` (expect exit 1), then
`setup.cmd --help` (exit 0). Enter `q` in the first terminal; a new setup run should
open its menu again. Do not run a hardware operation just to test locking.

There is no lock file to remove. A named
[Windows mutex](https://learn.microsoft.com/en-us/dotnet/api/system.threading.mutex?view=netframework-4.8)
is released when its process exits. Mutex access errors abort the operation rather
than bypass protection. Do not terminate active flashing just to release a lock.
After a crash, check the child tool and MCU: the mutex neither stops descendants
nor restores interrupted writes or settings.

Scope: one PC and a normalized case-insensitive absolute path. Junction, SUBST and
network aliases, and access from another PC, are not unified. Older script versions,
external tools and the same probe used from different directories are not protected.
Use the same directory path and operate on a shared probe sequentially.

## Short Release Description

Keep the text in `docs/releases/v<version>.md`: a short Russian description,
followed by the same English text inside `<details><summary>English</summary>`.
Link to the detailed changelog using an absolute URL pinned to the release tag:
RU uses `CHANGELOG.md`, EN uses `CHANGELOG.en.md`. Future-tag links work after publication.

1. Land release preparation on main and wait for successful CI for that exact commit.
2. Create a GitHub Release: tag `v<version>` at the verified commit, title
   `stm32-flasher <version>`, and description from the prepared file.
   The tag version must match `$VERSION` in `flash.cmd`.
3. Select Publish release. Saving a draft or simply pushing a tag does not start the build.
4. Wait for the Release workflow to succeed: it attaches the ZIP and `.zip.sha256`
   to the already published release. These files may be absent while the build runs.

The workflow does not create releases or change their title or description.
Check Actions on failure; rerun after resolving an external failure. Matching
asset names are replaced (`--clobber`); other assets are preserved. For code fixes,
prepare a new corrected tag instead of moving an already published tag.
Checking CI before publication remains the owner's manual responsibility.
This flow requires ordinary, non-immutable releases: immutable releases need
assets attached before publication and therefore a different workflow.

Reference: [release event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release),
[asset upload](https://cli.github.com/manual/gh_release_upload).

## Preview Without Hardware

```powershell
& "$tool/flash.cmd" -DryRun -HexFile firmware.hex -Engine OPENOCD -Target target/stm32f1x.cfg
& "$tool/erase.cmd" -DryRun -Engine JLINK -Device STM32F103C8
& "$tool/backup.cmd" -DryRun -Engine JLINK -Device STM32F103C8 -Size 65536
& "$tool/info.cmd" -DryRun -ProbeTarget -Engine JLINK -Device STM32F103C8
$LASTEXITCODE
```

DryRun does not run tools, query USB/MCU or change files. HEX checks are local:
format and checksums, not board compatibility. Exit 0 means a complete plan;
1 means invalid or missing data, without menus. Serial is optional; target/device
come from CLI or saved settings; backup size must be explicit.
CMD preserves the PowerShell exit code. Quote paths containing spaces.
Do not remove DryRun until the board and permission for the experiment are confirmed.
