# HOWTO

[Русский](../ru/HOWTO.md). PowerShell examples start at the clone root unless noted.
Examples do not authorize an agent to push or operate hardware.

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
CI does not validate physical SWD, reset or board restoration. Release publishing
is not yet automatically gated by CI. See [testing](../testing.md), in Russian.

## Workspace and inventory

```powershell
New-Item -ItemType Directory -Force tests/manual/01-probe-inventory
Set-Location tests/manual/01-probe-inventory
$tool = (Resolve-Path ../../..).Path
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
