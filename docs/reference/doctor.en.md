# Doctor Contract

[Русский](doctor.md) | **English**

Status: agreed contract; embedded passport and pure policy implemented.
The doctor.cmd wrapper, environment collection and user-facing output are not implemented yet.
The runtime version stays 0.3.0; the published tag is not changed.

## Scope

Info lists the environment. Doctor compares observations with requirements and
recorded release tests, without asserting that a board or HEX is ready to flash.
The future wrapper calls flash.cmd -Doctor. Other operating modes conflict.
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
and BaselineRelease. Codes are stable identifiers for future RU/EN messages.

Test-DoctorPolicy covers the passport, versions, ambiguity, proven blockers,
incomplete evidence and input preservation in PS5.1/7. Integration still needs
real CMD with stub executables, both languages, mode conflicts, early help/version,
no-query DryRun, bounded timeouts, and absence of writes or migration.
