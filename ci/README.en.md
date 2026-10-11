# CI Checks

[Русский](README.md) | **English**

## GitHub

[CI](../.github/workflows/ci.yml) runs on every branch/tag push, pull request and
manual dispatch. Two independent jobs use `windows-latest`:

- Validate (5 minutes): required files, PowerShell syntax, version format,
  changelog categories and strict specification structure/traceability (Python 3.12).
- Regression (15 minutes per shell): all `tests/Test-*.ps1` suites in Windows
  PowerShell 5.1 and PowerShell 7. A failure does not cancel the other matrix job.

Per-suite logs, timings, exit codes and `results.json` are uploaded even on failure;
`test-logs-powershell` / `test-logs-pwsh` artifacts are retained for 14 days.
New top-level `Test-*.ps1` suites are discovered automatically; `tests/manual` is excluded.
Tests use stubs, require no hardware and do not establish MCU compatibility.
They cover CMD entry points, engines, RU/EN, configuration, safety and packaging.

## Locally

Requires Windows, both shells and Python 3.12 on PATH. From the clone root:

```powershell
./ci/Invoke-Local.ps1
./ci/Invoke-Local.ps1 -Stage Validate
./ci/Invoke-Local.ps1 -Stage Regression -PowerShellExe pwsh
```

The first command runs validation and both shells sequentially.
Only this is the full local run; a single `pwsh` run does not replace the matrix.
`-PythonExe` and `-PowerShellExe` also accept full paths.
Missing shells or Python cause failure, not skipped coverage.
Failed suites are not masked; remaining suites continue.
A validation error stops the full run before regressions.

Default logs: `tests/.tmp-ci-logs/<timestamp-id>/1-powershell` and `2-pwsh`, ignored
by Git. Each local invocation is retained separately. Explicit `-LogDirectory`
preserves the previous behavior and reuses that path; choose different directories
for independent attempts. To run an individual suite:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Localization.ps1
pwsh -NoProfile -File tests/Test-Localization.ps1
```

`tests/Invoke-Tests.ps1` remains a compatible single-shell entry point.
GitHub uses the same `ci` scripts but runs shells in separate jobs.
A full run takes several minutes; live output and logs show progress.

## Fast Feedback

```powershell
./ci/Invoke-Local.ps1 -Profile Quick -List
./ci/Invoke-Local.ps1 -Profile Quick
./ci/Invoke-Local.ps1 -TestName Test-Localization.ps1,Test-TestRunner.ps1
```

Quick runs validation and six short suites: Ci, ExplicitSerial, Localization,
ProbeInventory, ReleaseNotes, TestRunner, in both shells by default. It covers
infrastructure and selected contracts, not a smoke test of all flashing commands.
For documentation start with `-Stage Validate`; for runtime changes add affected
suites. Quick does not replace CMD/engines, safety, configuration, packaging or
full CI before land. GitHub still runs Full.

`-TestName` accepts exact filenames, without paths or wildcards; unknown names
fail before tests start. It cannot be combined with Quick. `-List` only lists
suites, without validation, child processes or logs.
Console output and `run.json` record selection/discovery, Partial, timestamps,
host and status. `results.json` remains an array even for one test.
Status=Running means incomplete, not passed. This is not a source snapshot:
do not edit the tree during a run; capturing inputs is a separate next step.
A smaller selection improves feedback time, not full-suite performance.

## Releases and Hardware

[Release](../.github/workflows/release.yml) runs separately after the owner manually
publishes a release: it checks tag/version and attaches ZIP and SHA-256. Descriptions
are prepared in `docs/releases`. This does not replace checking the commit's CI result.
CMD files and both READMEs ship at the ZIP root; `ci` is not included.

After push, the owner checks CI for the exact commit, then runs `git land`.
Hardware acceptance remains separate: [rules and coverage (RU)](../docs/testing.md).
