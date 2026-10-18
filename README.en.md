# stm32-flasher

[Русский](README.md) | **English**

A portable STM32 command toolkit for ST-Link and J-Link. All logic lives in
standalone `flash.cmd`; the other CMD files are short aliases.
Requires Windows 10/11, Windows PowerShell 5.1 or PowerShell 7 and probe drivers.

Version **0.3.1**: `doctor` environment diagnostics and the script SHA-256 in `info`.

## Quick Start

Copy all CMD files from the repository's `bin` (or the release ZIP root) into
your firmware directory. These examples use CMD; prefix names with `./` in PowerShell.

```bat
info.cmd
setup.cmd
flash.cmd
```

`info` lists the environment and USB probes without connecting to the MCU.
`setup` changes the engine and probe after confirmation, without flashing.
`flash` immediately programs the only HEX file, or offers a menu for several files.
You can also pass a HEX argument or drag it onto `flash.cmd`.
Multiple probes without a saved selection require a choice.

## Commands

| Command | Action |
| --- | --- |
| `flash` | Program and verify firmware |
| `check` | Read and compare only HEX ranges, without writing |
| `erase` | Erase all Flash |
| `backup` | Save Flash as Intel HEX with SHA-256 |
| `halt` / `go` / `reset` | Halt / resume without reset / reset and run |
| `info` | Tools, versions, settings, probes and local HEX files |
| `doctor` | Compare the environment with the release baseline, without MCU access or settings changes |
| `setup` | Reconfigure while preserving history and firmware |
| `forget` | Remove settings and working artifacts; preserve firmware and backups |

Every command supports `--help`, `--version`, `-Lang ru` / `-Lang en`.
Help/version perform no operations and do not read settings.
[Doctor](docs/reference/doctor.en.md) reports OK/WARN/ERROR,
exit 0 when there are no ERROR findings. A different tool version is WARN,
not proof of incompatibility. Diagnostics do not confirm board readiness.
`-DryRun` validates the plan, HEX and supplied SHA-256 locally, without hardware,
external tools, network or file changes. Exit 0 means a ready plan, not MCU success.

## Engines and Limits

- **STM32CubeProgrammer**: installed CLI, ST-Link or J-Link.
- **OpenOCD**: installed or automatically downloaded, ST-Link;
  `st-info` assists STM32 identification for flashing.
- **SEGGER J-Link Commander**: installed CLI, J-Link and an MCU device name.

OpenOCD/ST-Link and SEGGER/J-Link support `halt/go/reset`;
CubeProgrammer/ST-Link supports only `halt/reset`. Unsupported combinations
fail without automatically switching engines.
OpenOCD `check` and core control require an explicit or saved target;
SEGGER requires a device. These operations do not auto-detect the MCU.

`check` may leave the core halted; it neither resets nor resumes it.
Halting the core does not guarantee that peripherals or watchdogs stop.
CubeProgrammer/J-Link skips the problematic post-flash `-rst`;
starting the application may require a separate reset.

Confirmed on STM32G474RE/ST-Link: `check` through CubeProgrammer/OpenOCD,
OpenOCD core control and CubeProgrammer `halt/reset`. On STM32F103CB/J-Link,
SEGGER `halt/go/reset`, flashing and `check` are confirmed.
This is not a guarantee for every MCU/tool version; see [test records (RU)](docs/testing.md).

## Working Files

Data belongs to the **calling directory**, even when CMD is invoked by full path:
`.flash.json` (settings), `.tools` (local tools), `flash_log.txt`, `report.html`,
`.history` (session history) and `backups` (firmware backups).
Legacy settings migrate to JSON during a working operation or confirmed setup;
`info` and `DryRun` do not migrate files.
A checksum found next to the HEX is verified before programming.
Successful reports are saved quietly; failed operations open the report in a browser.
The directory lock prevents concurrent operations there, not access to one probe from different directories.

[User guide (RU)](docs/user-guide.md) · [Settings](docs/reference/launch-configuration.md#english) ·
[CHANGELOG](CHANGELOG.en.md) · [Releases](https://github.com/ViacheslavMezentsev/stm32-flasher/releases) ·
[CI and local checks](https://github.com/ViacheslavMezentsev/stm32-flasher/blob/main/ci/README.en.md)
