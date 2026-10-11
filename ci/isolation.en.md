# Test Isolation

[Русский](isolation.md) | **English**

## Code Audit

The standard runner starts each `Test-*.ps1` in a separate process. File-based
suites use unique `tests/.tmp-<name>-<GUID>` directories. Environment changes,
mock functions and Add-Type are process-local. The audit found no machine-wide
registry/environment writes or fixed-port listeners. This is code review, not
OS-enforced containment.

| Resource | Suites | Experimental isolation |
| --- | --- | --- |
| Mutex, working directory | DirectoryLock | Separate copy; mutex identity includes the full path |
| Hanging descendants, PID files | InventoryTimeout | Private EXE/directory and whole-process-tree supervision |
| ZIP, dist, GITHUB_OUTPUT | PackageLayout | Packaging runs inside its own fixture |
| Settings, menu answers, env | Setup, LaunchConfig | Separate cwd/TEMP/TMP and process |
| Nested runners, pipes, deadlines | TestRunner | Private logs and confirmed descendant termination |
| Many CMD launches and EXE stubs | CoreControl, Verify, FlashEntry | Separate copies; full comparison still required |

GUID directory names alone do not prove concurrency safety: TEMP, inherited module
paths, descendants and CPU/disk contention remain shared risks. Keep copy paths
short for Windows PowerShell 5.1 and nested fixtures.

## Method

One clean-commit snapshot, identical suite list/order, a separate archive copy
for EVERY suite with both one and two workers. The limit counts active suites,
not all descendant processes. Verify SHA-256 before/after and isolate logs,
temporary directories and results. No hidden retry on failure.

A Windows Job Object owns the process tree before tests start: a bootstrap waits
until assignment succeeds. A surviving descendant means FAIL even when its parent
exits 0; terminate the tree and retain that evidence. Basis:
[Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects).
This is not an untrusted-code sandbox: user profiles, networking and devices are
not virtualized. Only existing hardware-free suites are used.

Python must not blindly pass a PS7 parent's `PSModulePath` to PS5.1: this made
`Get-FileHash` unavailable in the first sequential run. The prototype removes that
variable only from the child environment, letting the shell construct its own
standard paths. Preflight checks `Get-FileHash` and `Add-Type`. User/machine settings
remain untouched.

Synthetic scenarios cover colliding filenames, env, actual two-worker overlap,
nonzero exits, source mutation, timeout and leftover descendants. Then six suites
from the table are compared (excluding CoreControl/Verify/FlashEntry), in both
shells: PS5.1 1→2, PS7 2→1, with shell warmup before each mode. Preparation is
timed separately; all samples and failures are retained.

## Result on 2026-10-12

Clean commit `f135282`; Windows, i9-13900HX (24 cores / 32 logical processors),
Python 3.11.9, PS5.1.26100.9444 and PS7.6.6. One observation per mode/shell,
six of 23 suites. All 24 executions PASS: identical scope, no omissions or
duplicates, distinct paths, unchanged SHA-256 inputs and no remaining processes.

| Shell | Workers | Preparation, s | Execution, s | Total, s |
| --- | ---: | ---: | ---: | ---: |
| PS5.1 | 1 | 4.51 | 168.76 | 173.51 |
| PS5.1 | 2 | 8.07 | 93.24 | 101.37 |
| PS7 | 1 | 5.35 | 217.20 | 222.61 |
| PS7 | 2 | 8.13 | 135.88 | 144.07 |

Total includes final integrity checks; execution includes per-copy verification.
Observed total-time speedup: 1.71x / 1.55x, not a prediction for GitHub or the
entire suite. Preparation also varied between attempts; one sample cannot
establish its stable cost.

The original sequential PSModulePath FAIL is retained and excluded from the
comparison. After the fix, synthetic contracts passed again in PS5.1/7, followed
by all four real modes on the same snapshot. Runtime CMD, test thresholds,
version and standard workflow are unchanged.

## Next Step

One observation per mode does not establish a stable speedup. Six suites do not
replace the full 23-suite matrix. Standard local/GitHub CI remains sequential
within each shell; the research prototype is not included in CI or releases.

The mechanism is now available in opt-in ci/Invoke-Isolated.ps1 with regression
contracts: private copies, a 1/2-worker queue, Job Objects, per-suite and overall
shell deadlines, and complete-evidence checks. Test-IsolatedRunner joins the
standard suite (now 24 suites). Usage: [CI](README.en.md).
Full repeat on 2026-10-12, WorkingTree, 2 workers, Python 3.11.9:

| Shell | Suites | Preparation, s | Execution, s | Total, s |
| --- | ---: | ---: | ---: | ---: |
| PS5.1.26100.9444 | 24/24 PASS | 28.78 | 389.40 | 418.42 |
| PS7.6.6 | 24/24 PASS | 29.94 | 519.07 | 549.07 |

No omissions/duplicates, all copy integrity checks passed, no leftover processes.
In the first attempt, Test-Ci on PS7 returned zero but its Job Object still had
one active process; the outer runner correctly retained Failed. Its image was
not recorded then. The runner now allows up to one second for tree teardown
after root exit and records PIDs/images; persistent descendants still fail.
The short-lived-child contract passed; the full repeat did not reproduce the
original case. Original failure evidence is retained.

This is one full two-worker observation, not a full 1/2 comparison or GitHub
validation. Relative-path resolution in the PS wrapper was corrected after
capture; the final 8/8 runner contracts passed separately in both shells.
Next: a GitHub runner trial and a comparable full one-worker baseline.
Check long-suite scheduling and the overall deadline separately. Quick must not
replace full coverage; accept speedups only with identical scope, no missing or
duplicate suites, and preserved failure reporting.
