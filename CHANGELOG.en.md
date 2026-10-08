# Changelog

## [Unreleased]

### CI
- Windows checks run on every branch/tag push, pull request and manual dispatch. All `tests/Test-*.ps1` suites are discovered automatically and run in PowerShell 5.1 and 7, with logs retained for 14 days. Strict specification validation uses a versioned checker copy.

### Documentation
- Adapted AGENTS for the standalone CMD tool while retaining `<agent>/<task>` branches, signed commits and push/CI/land without PRs. Added TODO and RU/EN maintenance/HOWTO notes with known commands; simplified local research rules.
- Specification revision 1.3 requires flash to fail when an explicitly requested serial is not found, without selecting another probe or accessing its MCU. TC-32–TC-34 are defined; full safe DryRun remains pending.
- Specification revision 1.2 defines Info with DryRun as plan-only: no external tools, USB queries or MCU connection, even with ProbeTarget. TC-30–TC-31 are specified; implementation remains pending.
- Specification revision 1.1 resolves incomplete DryRun plans: no prompts, exit codes 0/1, actionable diagnostics and optional serial. Requirements and test cases are defined; implementation remains pending.
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
