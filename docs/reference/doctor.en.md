# Doctor Contract

[Русский](doctor.md) | **English**

Status: embedded passport, policy, doctor.cmd, environment collection and RU/EN
output are implemented; tests use EXE stubs without MCU access.
The runtime version is 0.3.1; the passport retains the 0.3.0 test baseline.

## Scope

Info lists the environment. Doctor compares observations with requirements and
recorded release tests, without asserting that a board or HEX is ready to flash.
The wrapper calls flash.cmd -Doctor. Other operating modes conflict.
Engine/Probe/Serial/Target/Device overrides, Lang, help, version and DryRun are supported
by the contract; CLI overrides saved settings.

No prompts, MCU connections, st-info --probe, network, downloads, migration or fixes.
No reports, history, command files or settings are written. Help/version bypass
configuration reads. DryRun describes the plan without external processes or USB.
Tool queries and output draining have separate bounded waits. Stale cached data
must not be substituted for a failed observation.

## Passport

JSON is embedded in Get-DoctorPassport within flash.cmd; no external dependency.
schemaVersion=1; baselineRelease=0.3.0. The baseline does not automatically follow
VERSION: it identifies the release that supplied evidence.

- runtime: Windows 10/11, PowerShell 5.1/7; supported families, not an exact PC image.
- tools: exact tested versions, no invented minimum requirements.
- profiles: engine/version/probe/mcu/operations/evidence; not an exhaustive list.
- evidence: separate hardware records and stub-CI links.

Initial baseline: CubeProgrammer 2.19.0 and SEGGER V8.32. Hardware records for
OpenOCD 0.12.0 lack full build identity, so its exact testedVersions list is empty.
Build suffixes remain significant. A v/V prefix and Cube file-version fourth
zero component are normalized; other parts are preserved. A profile's MCU name
does not identify the attached MCU or establish a hardware-profile match.

## Statuses

| Observation | Status |
| --- | --- |
| Supported runtime, valid JSON, available selected engine | OK |
| Exact tested tool version | OK for version only |
| Different/unknown version or timed-out query | WARN |
| Missing settings / legacy without migration / pending selection | WARN |
| Multiple suitable probes without a selected serial | WARN |
| Failed/timed-out inventory or unknown serial preventing selection verification | WARN |
| Invalid runtime/JSON, selected engine missing or unable to start | ERROR |
| Reliably established absence of suitable/selected probe | ERROR |
| Unsupported engine/probe pair | ERROR |
| Explicit OpenOCD target missing | ERROR |
| Target/device unset, or target availability unknown | WARN; operation limitation |
| No st-info for OpenOCD without a target | WARN; auto-detection limited |

Unused engines are not requirements. Cube/J-Link supports flash/check but this
does not authorize core control; doctor never approves every operation at once.
A configured J-Link device name is not a verified MCU identity.

Exit 0 means no ERROR; WARN is allowed. Exit 1 means ERROR or diagnostic failure.
Every summary states that the MCU, power, SWD and image were not checked.

## Facts and Tests

Get-DoctorAssessment consumes facts without OS access or input mutation.
Runtime: Supported/Unknown/Unsupported; Config: Valid/Missing/Legacy/Invalid.
Engine has State Available/Missing/NotSelected/Unknown, Name, and VersionState
Known/Unknown/Timeout/Error. Error specifically means inability to start;
unrecognized output or an unsupported version option means Unknown.
Inventory.State: Known/Unknown/Timeout/Error. Known Count and UnknownSerialCount
cover only suitable probe types; UnknownSerialCount <= Count.
Probe has Type, SerialRequested and SerialFound. Target: Available/Unset/Missing/Unknown;
Device and StInfo are boolean presence facts. An unknown probe type does not
permit the collector to assert reliable absence of a suitable device.
Output contains Findings (Id/Status/Code/Actual/Expected), ExitCode, NoticeCode
and BaselineRelease. Codes are stable identifiers for RU/EN messages.

Test-DoctorPolicy covers the passport and pure policy. Test-Doctor runs real CMD
with EXE stubs in both languages: conflicts, early help/version, no-query DryRun,
timeouts, incomplete inventories, start failures and unchanged working files.

## Usage and Limits

```bat
doctor.cmd
doctor.cmd -Engine CUBEPROGRAMMER -Probe STLINK -Lang ru
doctor.cmd -Engine JLINK -Probe JLINK -Device STM32F103CB -Lang en
doctor.cmd -DryRun
```

Only the selected engine is queried for its version. ST-Link inventory uses
CubeProgrammer with help-confirmed `-l stlink-only`; the older `-l st` is never
called. J-Link uses only `ShowEmuList USB` and `q` through stdin.
Each query has a 10-second limit plus up to 1 second to drain output streams.
Unknown or incomplete inventories, including an unconfirmed empty J-Link
response, mean WARN. Without a selected type, available USB observations are
shown but incomplete lists cannot select a type: pass `-Probe` or run setup.
Missing engines are not downloaded automatically.
When J-Link inventory is unconfirmed, a separate bounded Windows query checks
present USB devices. Confirmed presence adds a WARN about unavailable SEGGER
access and possible driver/ownership issues. A failed or timed-out Windows
query proves neither presence nor absence. This does not validate or fix drivers.
NT 10 alone does not identify Windows 10/11: Server editions are outside the
support contract; an unavailable product type means WARN.
DryRun prints only a plan; it neither validates settings nor assesses the environment.
