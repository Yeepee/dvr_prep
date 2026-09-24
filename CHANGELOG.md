# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-09-24

### Added

- Added verbose mode with `-v` / `--verbose`.
- Added a progress bar and estimated time remaining in essential output mode.
- Added graceful interruption handling for `Ctrl+C` and `SIGTERM`.

### Changed

- Process MP4 files in ascending alphabetical order.
- Capture the input file list before processing.
- Publish output files only after successful conversion.

### Fixed

- Remove incomplete output files after interrupted conversions.
- Preserve filenames containing spaces and special characters.
- Prevent invalid progress values from causing shell errors.

## [1.0.0] - 2026-09-24

### Added

- Initial release of `drv_prep`.
