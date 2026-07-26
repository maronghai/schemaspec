# Changelog

All notable changes to Rune will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

## [0.21.0] - 2026-07-27

### Fixed
- `--stats` flag now works for diff, migrate, reverse, and validate commands (previously only worked for compile)
- Added missing error handlers for `--target` flag (UnknownTarget, MissingTargetValue)

### Changed
- Help text updated with examples for new flags

## [0.20.0] - 2026-07-27

### Added
- `--stats` / `-s` flag: print compilation statistics (table/field/template/view counts) after compilation
- `--check` flag: dry-run mode — validate schema without writing output, prints "schema is valid" on success
- `--quiet` / `-q` flag: suppress non-essential output (e.g. "Written to ..." messages)

## [0.19.0] - 2026-07-27

### Added
- `--help` / `-h` flag prints usage and exits with code 0

### Fixed
- `compilePipeline` no longer passes `undefined` for `io` parameter (latent crash risk)
- JSON Schema output now properly escapes table comments containing special characters (quotes, backslashes, newlines)

### Changed
- ARCHITECTURE.md: corrected stale module paths (e.g. `diff_fields.zig` → `diff/fields.zig`)

## [0.18.0] - 2026-07-27

### Changed
- Simplified `readFileOrStdin` calls in validate and reverse command handlers

## [0.17.0] - 2026-07-27

### Changed
- Refactored forward pipeline (`pipeline/forward.zig`)
- Simplified main.zig entry point

## [0.16.0] - 2026-07-27

### Changed
- Continued forward pipeline refactoring

## [0.15.0] - 2026-07-27

### Changed
- Further main.zig simplification

## [0.14.0] - 2026-07-27

### Changed
- Major refactoring of `pipeline/forward.zig` (187 additions, 176 deletions)
- Simplified main.zig

## [0.13.0] - 2026-07-27

### Added
- Diff/migrate pipeline improvements

## [0.12.0] - 2026-07-27

### Changed
- Internal refactoring

## [0.11.0] - 2026-07-27

### Changed
- Internal refactoring

## [0.10.0] - 2026-07-26

### Changed
- Internal refactoring
