# CI Checks

[Русский](README.md) | **English**

## Isolated Runner (Opt-in)

Windows only; default local/GitHub runs remain sequential within each shell.
Capture the current runner and validate static checks first:

```powershell
$snapshot = Join-Path $PWD.Path 'tests/.tmp-ci-snapshots/parallel'
./ci/Invoke-Snapshot.ps1 -Stage Validate -RunDirectory $snapshot
./ci/Invoke-Isolated.ps1 -SnapshotDirectory $snapshot -Workers 2
# Compare identical inputs:
./ci/Invoke-Isolated.ps1 -SnapshotDirectory $snapshot -Workers 1
```

Workers defaults to 1. All Test-*.ps1 suites run unless exact TestName values
are supplied; -List is supported and partial coverage is explicit.
PS5.1 and PS7 run sequentially, with up to two suites active per shell.
An available worker takes the next suite. Each suite has private sources,
cwd, TEMP/TMP and a Windows Job Object. After the root exits, the tree gets up
to one second to settle; remaining descendants are terminated and reported as
failures. Initial process counts and settling time are recorded.
This prevents accidental conflicts, not hostile code.

-SuiteTimeoutSeconds defaults to 600; -RunTimeoutSeconds defaults to 1800
per shell, including preparation, checked between phases and during execution.
Cancellation/global timeout stops active process trees and queued work, returns
failure and prevents the next shell from starting. Ordinary suite failures do
not cancel other suites. Interrupted/incomplete runs cannot pass.

Evidence goes to fresh tests/.tmp-ci-isolated/<id>/<index-shell> directories.
An explicit -LogDirectory must also be new; previous evidence is never replaced.
run.json/results.json record selection, partial coverage, durations and status;
numbered directories retain copies, stdout/stderr, suite logs and result.json.
SHA-256 integrity is checked before/after. Exit zero without consistent results
is insufficient. The parent prints suite completions; live details are in logs.
Compare 1/2 workers using one snapshot without other heavy runs. The runner must
match the captured implementation; older snapshots lacking it cannot be used.

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

Snapshot tests also require Git on PATH. GitHub installs Python 3.12 in each
regression job; no third-party Python packages are needed.

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

## Source Snapshots

Before adding concurrency: [isolation audit and 1/2-worker comparison](isolation.en.md).

```powershell
./ci/Invoke-Snapshot.ps1 -Kind WorkingTree -Profile Quick
# Full clean-HEAD run before integration:
./ci/Invoke-Snapshot.ps1 -Kind Commit
```

WorkingTree captures current tracked and nonignored new file bytes, preserving
deletions. Commit requires a clean tree and uses `git archive HEAD`, including
export-ignore/export-subst attributes. The manifest distinguishes these inputs.
Git metadata and ignored logs, firmware and caches are excluded. Nonignored
personal files ARE included: inspect `git status` first. Symlinks, junctions and
submodules are rejected until a separate capture recipe is provided.

Do not edit during capture: a second inventory/byte pass rejects changes. Once
captured, the original tree can be edited while checks run in the separate
`source` copy. This is not an atomic filesystem snapshot or an untrusted-code sandbox.

Each attempt creates `tests/.tmp-ci-snapshots/<timestamp-id>` with `source.zip`,
`manifest.json` (HEAD, dirty, UTC, per-input and ZIP SHA-256), `source`, `console.log`,
`logs`, and `outcome.json` (parameters, versions, status, integrity and capture/check/
verification durations). Check time includes querying process versions. An explicit
`-RunDirectory` must be new; existing destinations are never reused. Failed and
incomplete attempts are retained; Creating/Running do not mean success. Before/after
integrity checks reject changed inputs, archive or manifest. New outputs are allowed
only under `tests/.tmp-*`, `tests/manual`, `docs/research`, `dist`, `__pycache__`;
captured inputs there are still hashed. This detects accidental changes, not code
deliberately forging evidence.

`-Stage`, `-Profile`, `-TestName`, `-PowerShellExe`, `-PythonExe` forward to local CI.
Full remains the default; Quick/selected suites are partial coverage, recorded in
`logs/*/run.json`. Full GitHub CI remains unchanged.

## Controlled Measurements

After checks finish, with no other CI runs, select the snapshot directory:

```powershell
$run = 'tests/.tmp-ci-snapshots/<timestamp-id>'
python -B -X utf8 "$run/source/ci/benchmark.py" --snapshot $run
```

The Windows-only benchmark sequentially starts PS5.1/7 directly and through CMD:
empty processes and reading/parsing the captured `flash.cmd`, never executing it
or accessing an MCU. Each combination gets 2 warmups and 2 series of 8 samples;
order is seeded/shuffled and mirrored in the second series. Warmups are excluded
from statistics. Options: `--warmup`, `--rounds`, `--repeats`, `--seed`, repeated
`--host`. Run the captured benchmark implementation.

A separate `benchmark-*.json` retains every sample, versions, parameters, manifest/
benchmark SHA-256, and per-series median/range. Nonzero exits or a 30-second timeout
stop the run as Failed without discarding earlier samples. Final integrity is checked.
Compare series on identical inputs and hardware; these are startup/parse costs,
not a full-CI speedup. Suite parallelism is opt-in only.

Controlled run on 2026-10-11 (PS5.1.26100.9444 / PS7.6.6, Python 3.11.9):
empty-process medians across two series were 99/103 ms direct and 669/655 ms
through CMD for PS5.1; 150/150 ms and 703/697 ms for PS7. Parsing added roughly
20–60 ms, CMD about 550 ms. This is one Windows machine, not a performance
threshold or proof of the delay's cause (such as antivirus). The local run does
not substitute for GitHub testing with Python 3.12.

## Suite Selection

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
