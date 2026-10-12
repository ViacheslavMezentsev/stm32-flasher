# Changelog

All notable changes to this project are documented here.
Based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]: Preparing 0.3.0: core control and unified configuration

### Added

- Manual GitHub CI comparison: one shared snapshot, full 1/2/2/1-worker trials on one VM per shell, raw timings and medians, separate artifacts. Incomplete/failed evidence prohibits speedup claims; orchestrator contracts join CI. CI defaults are unchanged; remote measurements have not run yet.

- Opt-in isolated CI runner with 1/2 workers: captured inputs, private copies and TEMP/TMP, process-tree supervision, timeouts and retained results. Regression contracts cover collisions, cancellation, failures, integrity and incomplete evidence. Local/GitHub defaults, runtime CMD and version are unchanged.

- RU/EN test isolation audit and same-snapshot one/two-worker comparison method. The local research harness separates source copies, TEMP/TMP and process trees; standard CI is unchanged. Found a PS5.1-from-Python dependency on inherited PS7 PSModulePath; the harness corrects the child environment and checks it before execution.
- Limited comparison: 6/23 suites, 1/2 workers, PS5.1/7, all 24 executions passed with unchanged inputs and no remaining processes. Total time improved by 1.71x/1.55x; a single local observation does not establish full-CI or GitHub speedup.

- Local CI source snapshots: WorkingTree/clean Commit, archive and SHA-256 manifest, separate logs and integrity checks. Sequential PS/CMD startup benchmark with warmups and repeated series; snapshot contracts in both shells. No suite parallelism or runtime command changes.

- Add local Quick, exact suite selection and listing without execution. Mark partial coverage in console/run.json; keep single-test results.json as an array. Separate default logs by attempt. Full CI and runtime commands remain unchanged.

- Add `ci` with RU/EN GitHub/local check documentation, shared Validate/Regression/All entry points and failure-propagation tests. The existing tests runner remains compatible.

- `halt.cmd`, `go.cmd`, `reset.cmd`: thin `flash.cmd -Command` wrappers sharing settings, probe selection, directory locking, reports and history. No HEX required, Flash programming/erasing or configuration cleanup.
- Core control through OpenOCD/ST-Link and SEGGER/J-Link; CubeProgrammer/ST-Link supports halt/reset using HOTPLUG to avoid a connection-time reset. CubeProgrammer go and its J-Link control combinations are rejected before MCU access; no automatic engine switching.
- Success requires exit 0 and the expected core state; errors/unknown output return 1 without retrying another serial. Test-CoreControl uses real CMD and stub executables; hardware validation remains pending.
- After adding core control, all 21 suites passed locally in PS5.1/7, including 120 new scenarios, help, locking, localization and packaging. Branch CI is pending push.
- The new comparison command is named `check` to avoid the CMD built-in `verify`. The experimental `-Command verify` is no longer accepted; existing history is unchanged.
- `check.cmd` / `flash.cmd -Command check`: read Intel HEX ranges and compare bytes on the PC using CubeProgrammer, OpenOCD or J-Link. No programming, erasing, reset or automatic resume commands; the core may remain halted. Gaps are not read. Reports and history identify the operation as check.
- Validate HEX, overlaps, address bounds and SHA-256 before MCU access; read failures and mismatches return 1. Add CMD tests with stub executables, RU/EN help, DryRun and wrapper packaging. Hardware check coverage is described above.
- The existing 19 suites passed in PS5.1/7; after test-harness fixes, the new Test-Verify passed separately (72 cases per version). CI after push is still pending.

### Changed

- Switch ordinary GitHub CI to the isolated two-worker runner per shell, with full suite discovery and captured sources. Runner budget is 25 minutes within a 30-minute job; artifacts retain the manifest, reports and logs without working copies. Local defaults remain unchanged. Experiment 38186953080 passed 200/200 suite executions, with median speedups of 1.608x (PS5.1) / 1.513x (PS7); one experiment is not a timing guarantee.

- Increase the GitHub CI regression job limit from 15 to 30 minutes after the full PS5.1 run was cancelled at the time limit. Test coverage and sequential execution are unchanged; this provides headroom, not a CI speedup.

- Split README into Russian and English files with language tabs; ship both in the ZIP. Clarify verified commands and scope for the upcoming 0.3.0. Simplify AGENTS while preserving branch/push/CI/land rules. Group changelogs into three categories with short release summaries, retaining historical entries.

- Tested halt/reset on AT32F403ACGU7 with SEGGER V8.32 at the default 4000 kHz, without Flash writes/erase. Fixed false failures parsing the EoE acknowledgement (`will now exit on Error`) and IsHalted with a PC address. Stubs now include real output formats; actual errors still fail. Separate go found an already running core and failed; check was not run without HEX. This is neither AT32 flashing support nor STM32/J-Link acceptance.
- The owner's logs confirm JSON setup: saving OpenOCD, loading through info, cancellation with unchanged SHA-256, switching to CubeProgrammer with openocdTarget cleared, and returning to OpenOCD with an explicit target (exit 0, JSON and info). The agent performed no MCU operations for this check.
- The owner subsequently confirmed OpenOCD check on STM32G474RE/ST-Link with target/stm32g4x.cfg (3.655 s) and separate go using the saved target (1.694 s). Console output confirms matching HEX ranges and the expected core state after go. The new J-Link commands and hardware check failure cases remain untested.
- The owner confirmed normal CubeProgrammer flashing (3.514 s) followed by check (1.089 s) on STM32G474RE/ST-Link: MCU bytes matched the HEX ranges. Evidence is the supplied console output, not an agent rerun; whole-Flash contents, post-check core state and hardware failure cases were not verified. OpenOCD check and the new J-Link commands still await hardware validation.
- The OpenOCD speed parsing fix is merged into main (ea7e045); branch and main CI passed.
- Fixed a false OpenOCD core-control failure on the informational adapter speed fallback message. Only the exact informational line is excluded; real errors, missing state and nonzero exit still fail. OpenOCD halt/go/reset and CubeProgrammer halt/reset were tested on STM32G474RE/ST-Link without Flash writes. State after disconnect is not guaranteed; new J-Link commands remain untested on hardware.

- Consolidate settings in `.flash.json`, schema version 1. Operational runs or confirmed setup migrate legacy files; JSON takes precedence. Writes use a temporary file and atomic replacement, followed by legacy cleanup after JSON validation.
- Info/DryRun never migrate; help/version never read settings. Invalid JSON fails before discovery; explicit ResetConfig/forget clears both formats. Add migration, write/deletion failure, RU/EN and argument-priority tests; include the format guide in release ZIPs.
- Following JSON integration, all 19 suites passed locally in PS5.1/7 without an MCU; the strict specification check is clean. CI results for this stage are not yet confirmed.
- The owner confirmed JSON migration and successful programming with verification through CubeProgrammer/ST-Link (3.406 s), based on console output and the generated settings file. A subsequent info run confirmed JSON loading and the saved engine and probe selection.
- Move CMD files into the repository's `bin`. Release ZIP commands remain at the root for copying beside firmware; runtime data stays in the working directory.
- Update CI and packaging paths. Test-FlashEntry covers both CMD layouts with stub executables; Test-PackageLayout executes the release workflow packaging block and checks SHA-256, unchanged CMD files and portable RU/EN help entry points.
- All 18 suites and the strict specification check passed locally in PS5.1/7. No hardware operations were performed; GitHub CI is pending the push.

### Fixed

- Fixed the cause of standalone go failing after halt: Commander resumes the core on close by default. Only halt sets SetRestartOnClose=0 before stopping; go remains resume without reset. Reset, check and flashing sequences are unchanged, and real errors are not suppressed. The EXE stub checks the exact sequences of all three commands.
- The owner's STM32F103CB/J-Link log confirms halt/reset, flash and check; go failed in the original version. This is separate evidence, not an agent flashing rerun.

- Quote the HEX path passed to CubeProgrammer, including fallback arguments, so directories containing spaces do not split it. The new CMD test reproduced the defect before the fix.

## [0.2.12] - 2026-10-10: Fix no-argument startup

### Changed

- Record the 0.2.11 release, successful CI for all 16 suites in PS5.1/7 and Release in TODO. Independent verification of the downloaded ZIP remains pending due to an environment network error. Propose a tagged-commit CI gate before asset building; workflow behavior is unchanged.

### Fixed

- The owner confirmed no-argument startup with a single HEX: CubeProgrammer/ST-Link programming and verification succeeded (3.584 s).
- Fix silent exit when running `flash.cmd` without arguments (issue #1). In 0.2.10–0.2.11, CMD quote substitution on empty FLASH_ARGS corrupted the PowerShell invocation; 0.2.9 was unaffected. Escape quotes only when arguments are present.
- Add Test-FlashEntry with real CMD launches and stub executables for CubeProgrammer, OpenOCD and J-Link. Cover a single HEX without arguments, fresh/saved configuration, explicit paths, no HEX, invalid multiple-HEX selection, tool failures, missing verification markers and SHA-256 mismatch. Reports and history are checked after a real child process; no MCU is used.

## [0.2.11] - 2026-10-09: Setup and concurrent-operation protection

### Added

- Flash/erase/backup/setup/forget/ResetConfig and info with ProbeTarget acquire a shared directory lock before hardware access or writes. A second run immediately reports a localized busy message and exits 1. Help/version, DryRun and basic info bypass the lock.
- A named mutex is released when its process exits, without lock files. Scope is one PC and a normalized path; junction/SUBST/network aliases are not unified. This neither protects one probe across directories nor recovers interrupted operations.
- Add TC-37 with two processes and forced owner termination, without MCU access.

- Add `setup.cmd` (`flash.cmd -Setup`): select engine and probe, optional target/device, confirm or cancel. Automatic probe selection is type-specific; saving clears stale incompatible settings but preserves firmware, logs, history and tools.
- Help/version and DryRun exit without discovery or writes; the wizard neither connects to an MCU nor downloads tools. Add hardware-free checks and package the new wrapper.
- Honor the saved probe type during automatic engine selection. With a saved type and no serial, multiple devices require a menu rather than selecting the first J-Link.

### Changed

- All 15 suites passed in PowerShell 5.1/7; the strict specification check is clean. Verified 15 local ZIP files, SHA-256 and RU/EN help/version for all six commands.
- Owner logs confirm switching from CubeProgrammer/ST-Link to J-Link, cancellation before saving, rejection of a second setup, help/info availability while locked and reopening after release. No MCU writes or erasure were performed.
- Add Test-Localization for RU/EN keys, nonempty translations, placeholder indices and literal T calls; expand help checks for all commands to both languages. CI discovers the suites in PS5.1/7; translation quality still requires human review.

- Record the 0.2.10 release, CI/Release results and pending downloaded-archive verification in TODO; propose concurrent-operation protection as the next step, without code changes.

## [0.2.10] - 2026-10-09: Safe DryRun and expanded checks

### Added

- Add TC-17 through CMD wrappers: ResetConfig/Clean/DryRun, preservation of HEX, SHA-256, backups, CMD files, documents and unknown tools; rejection of junctions at cleanup paths, inside history or at the `.tools` parent. Check contents of a control directory outside the calling directory. Cleanup implementation is unchanged; CI discovers the test for PS5.1/7 automatically.

- Plan before discovery: every command with `-DryRun` avoids external tools, USB/MCU queries, network access, prompts and file changes. Values include their sources; invalid/incomplete plans return 1, complete plans return 0 without claiming hardware success.
- Validate local Intel HEX records, lengths, checksums, EOF and nonempty data, plus SHA-256 when supplied. MCU memory compatibility is not checked. Specification updated to revision 1.4.
- Add guarded CMD-process regression tests for PS5.1/7, automatically discovered by CI. Preserve quoted paths containing spaces and nonzero PowerShell exit codes in the CMD launcher.

### Changed

- Add `docs/releases/v<version>.md`: a short Russian description and collapsed English translation linking to CHANGELOG. The owner publishes the release manually with this text; the workflow runs on `release: published`, validates the version and attaches ZIP/SHA-256 without changing the title or description. Tag pushes no longer publish releases.

- Before 0.2.10, tested backup/erase/restore on a 128 KiB WeAct BluePill-Plus: CubeProgrammer 2.19.0 with ST-Link and J-Link, OpenOCD 0.12.0 with ST-Link, SEGGER Commander V8.32 with J-Link V9.60. Readback confirmed full erasure and byte-for-byte restoration. CubeProgrammer/J-Link required a separate reset to start the application, consistent with its documented limitation.
- Checked J-Link selection in the mixed-probe info menu and cleanup in a separate fixture while preserving firmware and backups. Production code was unchanged during hardware acceptance.

- Sequential sessions within one second no longer overwrite archives: occupied names receive `_1`, `_2`, etc., including incomplete older sets. Fix the history index link in new archived reports. Existing reports are not rewritten; this change does not protect concurrent runs.
- Add history retention regression coverage: preserved sessions, links, ordering and the latest 20 index rows without deleting older archives, PS5.1/7.
- Add TC-20 process tests for flash/erase/backup with mocked CubeProgrammer, RU/EN, success and failure; flash/erase also cover zero exit codes without success markers. Check HTML, JSON, archived files, index links, timestamps, duration and browser policy. Production code is unchanged; CI discovers the suite for PS5.1/7 automatically.

- Stream stdout/stderr lines to the console while writing UTF-8 logs. Print each suite's PASS/FAIL, duration and exit code; add `DurationSeconds` to `results.json`.
- Test the runner itself: output and logs are available before suite completion, failures retain their exit codes and later suites still run. `flash.cmd` behavior is unchanged.

- With multiple PowerShell installations, the runner selects the first executable in PATH rather than concatenating executable paths.
- Fixed workflow validation before job startup: the step uses a literal pwsh shell and passes the matrix-selected PowerShell to the runner through an environment variable and `-PowerShellExe`.
- Added full PowerShell-process J-Link failure tests for SEGGER and CubeProgrammer in RU/EN: exit code, single explicit-serial attempt, report and history. A mutation control detects retries without serial; no hardware is used.
- Windows checks run on every branch/tag push, pull request and manual dispatch. All `tests/Test-*.ps1` suites are discovered automatically and run in PowerShell 5.1 and 7, with logs retained for 14 days. Strict specification validation uses a versioned checker copy.

- Adapted AGENTS for the standalone CMD tool while retaining `<agent>/<task>` branches, signed commits and push/CI/land without PRs. Added TODO and RU/EN maintenance/HOWTO notes with known commands; simplified local research rules.
- Specification revision 1.3 requires flash to fail when an explicitly requested serial is not found, without selecting another probe or accessing its MCU. TC-32–TC-34 are defined; full safe DryRun was not implemented at that revision.
- Specification revision 1.2 defines Info with DryRun as plan-only: no external tools, USB queries or MCU connection, even with ProbeTarget. TC-30–TC-31 are specified; implementation was added later, see DryRun above.
- Specification revision 1.1 resolves incomplete DryRun plans: no prompts, exit codes 0/1, actionable diagnostics and optional serial. Requirements and test cases are defined; implementation was added later, see DryRun above.
- Introduced the general specification draft revision 1.0 using embedded-tech-spec: stable requirement IDs, provenance, test cases, traceability and open questions. Archived the previous info-only revision 2 with a migration map. Distinguished planned DryRun behavior and hardware backup/restore procedures from existing functionality.

- Moved the user guide and testing instructions to `docs/`. Local research uses `docs/research/NN-name/`, manual workspaces use `tests/manual/NN-name/`; neither is included in Git or release packages.

### Fixed

- Bound J-Link output draining to 1000 ms after waiting up to 10000 ms for the tool: a descendant retaining stdout/stderr can no longer block enumeration indefinitely. This is not a flashing or whole-info timeout.
- Add TC-22 with real fixture processes: hangs, large stdout/stderr and inherited pipes. No hardware or installed probe tools are used; CI discovers the suite for PS5.1/7 automatically.

- ST-Link USB inventory rejects a confirmed missing explicit serial before MCU probing; unavailable or incomplete inventory preserves the serial for the engine. Selection, engine argument and retry-guard regression tests pass in PowerShell 5.1/7.
- J-Link timeouts are reported in the USB probes section with USB troubleshooting guidance; detected ST-Link probes remain visible.
- `info.cmd` uses CubeProgrammer `-l stlink-only` after checking option support, with Windows USB enumeration as fallback.
- Windows instance IDs are no longer displayed as probe serials. CubeProgrammer enumeration errors are reported; unknown device IDs remain available for diagnosis.
- Added PowerShell 5.1/7 regression tests, a reference entry and revision 1 of the change specification.

Previous release history is retained in [CHANGELOG.md](CHANGELOG.md).
