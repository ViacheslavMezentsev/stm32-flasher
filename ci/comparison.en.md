# GitHub Worker Comparison

[Русский](comparison.md) | **English**

Separate manual **CI Worker Comparison** workflow, ci-compare.yml.
Default CI uses two workers; this workflow separately compares 1/2 workers.
No hardware is used.

## First Result

[Run 38186953080](https://github.com/ViacheslavMezentsev/stm32-flasher/actions/runs/38186953080)
at 4e4f41c passed all eight full 25-suite trials. One/two-worker medians:
PS5.1 889.09/552.85 s (1.608x), PS7 735.26/486.08 s (1.513x).
This supports adopting two workers in ordinary CI, not a timing or reliability
guarantee across Windows runners. Subsequent pushes check stability.

## Owner Workflow

1. Signed commit and branch push, successful CI for that SHA, then git land.
2. Wait for main CI. In Actions select CI Worker Comparison, Run workflow, main.
   Before the first manual run the workflow must exist on the default branch:
   [GitHub rule](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
3. Inspect Summary and download comparison-source, comparison-powershell,
   comparison-pwsh. Retain the run URL and SHA.

Publishing the workflow does not mean the experiment has run.

## Conditions

- One job captures the checkout as WorkingTree: ZIP, source and SHA-256 manifest.
  Transfer includes hidden files. Both shells verify the same manifest.
- Two Windows jobs, PS5.1 and PS7. Within each VM run **1, 2, 2, 1 workers**
  sequentially, without Quick or subset selection. Currently 25 suites;
  new Test-*.ps1 files are included automatically.
- Each invocation uses the existing isolated runner: private copies/TEMP/TMP,
  identical warmup, process supervision and integrity checks. Suite order is fixed.
- Per-suite timeout 600 s; per-run budget 1800 s. Ordinary failures are retained
  and later trials still run; cancellation stops the sequence. Matrix failures
  do not cancel the other shell.
- Expect roughly 40–60 minutes per shell, not a guarantee. A 135-minute job limit
  leaves room beyond four 30-minute budgets. Shell jobs run concurrently and
  their runner-minute costs add up. Concurrency prevents simultaneous experiments.

## Interpretation

comparison.json records SHA, runtime versions/Windows image/CPU count, all four
raw reports and preparation, execution and total durations.
Compare median total times including preparation and verification:
median(1) / median(2). Below 1 means a slowdown. Compute it only when all four
full runs pass with matching inputs, suite inventories and versions.
Exit zero without reports is insufficient. Failure, changed inputs, omitted or
duplicate suites, leftover processes or incomplete runs prohibit speedup claims.
Running is not a successful result.

These are runner timings, excluding checkout, artifact transfer and outer
orchestrator startup. Inspect complete job durations separately.

Artifacts are retained for 14 days: source snapshot separately, summary and
per-suite logs separately. Generated EXE/fixtures and per-worker source copies
are not uploaded. Log upload uses always(), including on failure; abrupt job
termination may leave incomplete evidence.

ABBA reduces first-run bias but does not eliminate hosted-VM noise.
Two observations per mode cannot establish stable variability. Do not compare
PS5.1 vs PS7 as identical hardware: they use separate VMs. This does not compare
against the old non-isolated runner or automatically change CI defaults.

After collecting evidence, assess correctness, speedup and preparation costs;
repeat if necessary, then agree separately on changing the default.
