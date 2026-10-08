# Specification checker

`check_spec.py` is an unchanged copy of the embedded-tech-spec checker obtained
on 2026-10-08 from:
https://github.com/ViacheslavMezentsev/demo-stm32-skills/blob/main/embedded-tech-spec/scripts/check_spec.py

It was previously kept only in the ignored local research directory. This copy
is versioned so CI can run without fetching executable code from another project.
Updates must be reviewed explicitly. It checks document structure and traceability,
not firmware correctness or hardware support.

Run from the repository root:

```powershell
python -X utf8 tests/tools/check_spec.py docs/TECHNICAL_SPECIFICATION.md --strict
```
