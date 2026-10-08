# Working with the project

[Русский](../ru/maintenance.md)

1. Read [AGENTS](../../AGENTS.md), [README](../../README.md), [TODO](../../TODO.md)
   and both Unreleased changelogs. Consult the Russian specification and user guide.
2. Inspect the branch and dirty files. New work uses `<agent>/<task>` from updated
   main (`codex/`, `claude/`, `gemini/`, `dev/`, etc.). Preserve existing work.
3. Define behavior, add a reproducing test and make a narrow change in standalone
   `flash.cmd`; wrappers must not duplicate it. Agree release versions separately.
4. Run hardware-free tests in PS5.1/7 and the spec checker. Hardware experiments
   require authorization, a verified backup of all affected memory, restoration
   and verification after the experiment, including failures.
5. Update TODO, RU/EN changelogs and notes. Preserve specification IDs, history
   and coverage. Planned tests are not PASS results.
6. Review the diff for personal data and unrelated files. Prepare an approved,
   signed English Conventional Commit; never bypass a signing failure.
7. The owner pushes the work branch, checks CI and runs `git land` without a PR.
   Land fast-forwards main, pushes it and deletes the work branch. Stop on
   divergence; do not force-push or reset. The agent needs a separate explicit
   request for push, land, tags or releases. See [HOWTO](HOWTO.md).

At each stage completion, report the verified current branch and the next Git
commands. Keep push separate from land, which follows successful CI.

## Layout and documentation

Root: commands, README, changelogs, LICENSE, AGENTS, TODO and Git configuration.
`docs/ru` and `docs/en` hold contributor notes. Maintain these notes, README and
changelogs together in both languages. The specification and existing user/testing
guides remain Russian; local research does not require translation.

`tests/Test-*.ps1` contains hardware-free regressions; `tests/tools` the spec checker.
Research uses `docs/research/NN-name`, execution workspaces `tests/manual/NN-name`.
Both are ignored and must not supply required CI inputs. Release ZIP contents
use an explicit allowlist; development files are not automatically shipped.
