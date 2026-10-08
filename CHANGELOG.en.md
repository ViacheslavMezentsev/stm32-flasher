# Changelog

## [Unreleased]

### Release Descriptions
- Add `docs/releases/v<version>.md`: a short Russian description and collapsed English translation linking to CHANGELOG. The owner publishes the release manually with this text; the workflow runs on `release: published`, validates the version and attaches ZIP/SHA-256 without changing the title or description. Tag pushes no longer publish releases.

### Hardware Acceptance
- Before 0.2.10, tested backup/erase/restore on a 128 KiB WeAct BluePill-Plus: CubeProgrammer 2.19.0 with ST-Link and J-Link, OpenOCD 0.12.0 with ST-Link, SEGGER Commander V8.32 with J-Link V9.60. Readback confirmed full erasure and byte-for-byte restoration. CubeProgrammer/J-Link required a separate reset to start the application, consistent with its documented limitation.
- Checked J-Link selection in the mixed-probe info menu and cleanup in a separate fixture while preserving firmware and backups. Production code was unchanged during hardware acceptance.

### Reports and History
- Sequential sessions within one second no longer overwrite archives: occupied names receive `_1`, `_2`, etc., including incomplete older sets. Fix the history index link in new archived reports. Existing reports are not rewritten; this change does not protect concurrent runs.
- Add history retention regression coverage: preserved sessions, links, ordering and the latest 20 index rows without deleting older archives, PS5.1/7.
- Add TC-20 process tests for flash/erase/backup with mocked CubeProgrammer, RU/EN, success and failure; flash/erase also cover zero exit codes without success markers. Check HTML, JSON, archived files, index links, timestamps, duration and browser policy. Production code is unchanged; CI discovers the suite for PS5.1/7 automatically.

### CI Progress
- Stream stdout/stderr lines to the console while writing UTF-8 logs. Print each suite's PASS/FAIL, duration and exit code; add `DurationSeconds` to `results.json`.
- Test the runner itself: output and logs are available before suite completion, failures retain their exit codes and later suites still run. `flash.cmd` behavior is unchanged.

### Cleanup Safety
- Add TC-17 through CMD wrappers: ResetConfig/Clean/DryRun, preservation of HEX, SHA-256, backups, CMD files, documents and unknown tools; rejection of junctions at cleanup paths, inside history or at the `.tools` parent. Check contents of a control directory outside the calling directory. Cleanup implementation is unchanged; CI discovers the test for PS5.1/7 automatically.

### Inventory Timeouts
- Bound J-Link output draining to 1000 ms after waiting up to 10000 ms for the tool: a descendant retaining stdout/stderr can no longer block enumeration indefinitely. This is not a flashing or whole-info timeout.
- Add TC-22 with real fixture processes: hangs, large stdout/stderr and inherited pipes. No hardware or installed probe tools are used; CI discovers the suite for PS5.1/7 automatically.

### DryRun
- Plan before discovery: every command with `-DryRun` avoids external tools, USB/MCU queries, network access, prompts and file changes. Values include their sources; invalid/incomplete plans return 1, complete plans return 0 without claiming hardware success.
- Validate local Intel HEX records, lengths, checksums, EOF and nonempty data, plus SHA-256 when supplied. MCU memory compatibility is not checked. Specification updated to revision 1.4.
- Add guarded CMD-process regression tests for PS5.1/7, automatically discovered by CI. Preserve quoted paths containing spaces and nonzero PowerShell exit codes in the CMD launcher.

### CI
- With multiple PowerShell installations, the runner selects the first executable in PATH rather than concatenating executable paths.
- Fixed workflow validation before job startup: the step uses a literal pwsh shell and passes the matrix-selected PowerShell to the runner through an environment variable and `-PowerShellExe`.
- Added full PowerShell-process J-Link failure tests for SEGGER and CubeProgrammer in RU/EN: exit code, single explicit-serial attempt, report and history. A mutation control detects retries without serial; no hardware is used.
- Windows checks run on every branch/tag push, pull request and manual dispatch. All `tests/Test-*.ps1` suites are discovered automatically and run in PowerShell 5.1 and 7, with logs retained for 14 days. Strict specification validation uses a versioned checker copy.

### Documentation
- Adapted AGENTS for the standalone CMD tool while retaining `<agent>/<task>` branches, signed commits and push/CI/land without PRs. Added TODO and RU/EN maintenance/HOWTO notes with known commands; simplified local research rules.
- Specification revision 1.3 requires flash to fail when an explicitly requested serial is not found, without selecting another probe or accessing its MCU. TC-32–TC-34 are defined; full safe DryRun was not implemented at that revision.
- Specification revision 1.2 defines Info with DryRun as plan-only: no external tools, USB queries or MCU connection, even with ProbeTarget. TC-30–TC-31 are specified; implementation was added later, see DryRun above.
- Specification revision 1.1 resolves incomplete DryRun plans: no prompts, exit codes 0/1, actionable diagnostics and optional serial. Requirements and test cases are defined; implementation was added later, see DryRun above.
- Introduced the general specification draft revision 1.0 using embedded-tech-spec: stable requirement IDs, provenance, test cases, traceability and open questions. Archived the previous info-only revision 2 with a migration map. Distinguished planned DryRun behavior and hardware backup/restore procedures from existing functionality.

### Project layout
- Moved the user guide and testing instructions to `docs/`. Local research uses `docs/research/NN-name/`, manual workspaces use `tests/manual/NN-name/`; neither is included in Git or release packages.

### Fixed
- ST-Link USB inventory rejects a confirmed missing explicit serial before MCU probing; unavailable or incomplete inventory preserves the serial for the engine. Selection, engine argument and retry-guard regression tests pass in PowerShell 5.1/7.
- J-Link timeouts are reported in the USB probes section with USB troubleshooting guidance; detected ST-Link probes remain visible.
- `info.cmd` uses CubeProgrammer `-l stlink-only` after checking option support, with Windows USB enumeration as fallback.
- Windows instance IDs are no longer displayed as probe serials. CubeProgrammer enumeration errors are reported; unknown device IDs remain available for diagnosis.
- Added PowerShell 5.1/7 regression tests, a reference entry and revision 1 of the change specification.

Previous release history is retained in [CHANGELOG.md](CHANGELOG.md).
