# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project uses semantic versioning in `Major.Minor.Patch` form while it is still in active development.

## [0.2.3] - 2026-04-25

### Changed
- Updated release publishing so GitHub Release pages use the matching `CHANGELOG.md` section as the release description.

## [0.2.2] - 2026-04-25

### Added
- Added `CHANGELOG.md` to the repository and release package.
- Added a separate `.sha256` checksum file to release assets.

### Changed
- Updated CI to require `CHANGELOG.md` as part of the tracked release documentation set.
- Updated the release workflow to package changelog and publish checksum assets alongside the zip archive.

## [0.2.1] - 2026-04-25

### Added
- Added CI workflow to validate required files, PowerShell syntax, and version format.
- Added release workflow to publish tagged GitHub Releases with packaged artifacts.
- Added script version display in the console banner and HTML report.
- Added operator, account, machine, and network host details to the HTML report.
- Added local and UTC timestamps to the HTML report.
- Added total operation duration to both console output and HTML report.
- Added a detailed Russian usage guide.

### Changed
- Improved auto-flash flow when a single `.hex` file is present or passed directly.
- Preferred STM32CubeProgrammer automatically for direct non-interactive flashing when available.
- Changed successful runs to save the report silently without opening the browser.
- Kept automatic report opening only for failed runs.
- Improved report readability with section highlighting and alternating row backgrounds.
- Normalized progress-bar garbage characters in captured tool logs for cleaner reports.
- Removed the final keypress wait from the batch wrapper.
- Shortened the flashing status message to avoid promising a fixed duration.
- Updated README to stay short, bilingual, and aligned with the current script behavior.

### Fixed
- Fixed relative `-HexFile` resolution before working directory initialization.
- Fixed crashes on non-numeric interactive menu input.
- Fixed repeated misinterpretation of `ru` and `en` as firmware paths.
- Fixed use of invalid saved or passed OpenOCD target configs.
- Fixed missing Russian localization for the MCU section title.

## [0.1.0] - 2026-04-25

### Added
- Initial public baseline of the single-file STM32 flashing script.
- Built-in Russian and English localization.
- Support for STM32CubeProgrammer and auto-downloaded OpenOCD.
- HTML flash report and text log generation.
