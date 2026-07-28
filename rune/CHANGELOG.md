# Changelog

All notable changes to Rune will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

## [0.36.0] - 2026-07-28

### Architecture
- **Comptime RenderEntry validation**: Added compile-time check in `renderFromTable()` that validates render table length matches SqlType enum variant count. Catches silent mismatches when adding new SqlType variants.
- **TypedAst ss_symbol cleanup**: Renamed `TypedColumn.sym_type` → `ss_symbol` with documentation clarifying it's for SQLite roundtrip fidelity only.
- **Diff FK rename detection**: `diffFks()` now accepts field diffs and performs rename-aware matching. When a column is renamed and an FK references it, the FK diff produces `modify` instead of `drop + add`. Added `adjustFkForRenames()` helper and 3 new unit tests.

### Code Quality
- **Shared test helpers**: Extracted `makeTestColumn()` from 5 test files into `semantic/test_helpers.zig`.
- **Test extraction**: Moved ~310 inline unit tests from 35 production files into 30 new colocated `*_test.zig` files. Production files now contain only logic.
- **Dead code cleanup**: Removed unused imports, unused re-exports, and dead root test files.

### Documentation
- **`rune/README.md`**: New contributor README with project overview, quick start, commands, CLI flags reference, testing, and contributing guide.
- **ARCHITECTURE.md**: Fixed roundtrip test count (20 → 26), updated total.

## [0.34.0] - 2026-07-27

### Architecture
- **Diff format module split**: Refactored monolithic `diff/format.zig` (518 lines) into 4 files: `format.zig` (re-export), `format/text.zig` (text), `format/json.zig` (JSON), `format/sarif.zig` (SARIF).
- **SARIF version from source**: `format/sarif.zig` now reads `version.VERSION` from `version.zig` instead of hardcoding.

### Testing
- Updated 247 golden test files from version 0.32.0 to 0.34.0.

## [0.35.0] - 2026-07-28

### Fixed
- Re-enabled colocated test files (`diff/diff_test.zig`, `diff/fields_test.zig`, `codegen/codegen_test.zig`) that were disabled since v0.28.0 SqlType refactor
- Fixed 9 compilation errors across colocated test files: string→SqlType type mismatches, missing struct fields, deprecated `getWritten()` API, wrong namespace references
- Fixed test memory leaks in colocated tests using arena allocators
- Fixed golden file naming inconsistency: `view-basic-pg.sql` → `view-basic.pg.sql`, `view-basic-sqlite.sql` → `view-basic.sqlite.sql`
- Fixed `diff/indexes.zig` test using wrong `IndexDecl.IndexType` namespace
- Fixed `sqlite_hints.zig` COLUMN_RULES ordering: exact rules now precede prefix rules, so `is_active` matches with score 90 (exact) instead of 85 (prefix)
- Fixed `diff/semantic.zig` test: MySQL `tinyint` (→ `n`) and PG `smallint` (→ `i`) are correctly NOT semantically equivalent
- Fixed `reverse/map.zig` test: MySQL `int` correctly maps to symbol `n` (not `int`)
- Fixed `reverse/map.zig` decimal/numeric parameterized extraction: removed REVERSE_MAP entries that intercepted `decimal(P,S)`/`numeric(P,S)` before parameterized extraction code; added internal space removal for `decimal(16, 2)` → `16,2`
- Fixed `types/reverse_map.zig` passthrough entries: added `rev_priority = 10` so passthrough types (uuid, real, float4, etc.) don't incorrectly beat canonical entries
- Updated data validation tests to account for passthrough entries with `rev_priority = 10` and `confidence_base = 70`

### Added
- `tests.zig` test module index for colocated test files
- Second test step in `build.zig` for colocated test compilation
- Comptime RenderEntry table length validation in `dialect/dialect.zig` (reverted — not applicable to tagged unions)

### Changed
- Updated `rune/ARCHITECTURE.md` testing table with correct test counts (MySQL 86, PG 85, SQLite 25, JSON Schema 3)

## [0.33.0] - 2026-07-27

### Changed
- Extracted shared reverse mapping data to `types/reverse_map.zig` (canonical location for `REVERSE_MAP` and `ReverseMapping`)
- `reverse/map_data.zig` now re-exports from `types/reverse_map.zig` (backward-compatible)

### Added
- 25 new unit tests in `reverse/map.zig`: round-trip tests (SS symbol → SQL type per dialect), confidence score range validation, data integrity checks
- `tests.zig` test module index for colocated test files (commented out pending pre-existing test fixes)
- Colocated test files moved to module directories: `diff/diff_test.zig`, `diff/fields_test.zig`, `codegen/codegen_test.zig`

## [0.29.0] - 2026-07-27

### Added
- Validation for unknown `--format` values (returns error.UnknownFormat)
- Updated help text with complete flag documentation for all commands

## [0.28.0] - 2026-07-27

### Added
- `--format json` flag for migrate command: output migration as JSON
- Diff output now shows user-friendly SQL type names instead of raw AST tags

## [0.27.0] - 2026-07-27

### Added
- `--strict` flag: treat warnings as errors (useful for CI/CD pipelines)
- Centralized version management via `version.zig` module

### Changed
- Version constant now lives in single `version.zig` module (single source of truth)

## [0.26.0] - 2026-07-27

### Added
- `--format json` flag for diff command: output diff as JSON for programmatic consumption
- `--validate-only` flag for reverse command: validate SQL without generating .ss output

## [0.25.0] - 2026-07-27

### Added
- `--dry-run` flag for migrate command: show migration SQL without writing to file
- JSON Schema now handles negative numbers in CHECK constraints

## [0.24.0] - 2026-07-27

### Added
- Diff output now shows old and new values for comment and engine changes
- Diff output now shows added/removed metadata with context

### Changed
- Optimized diff engine with pre-allocated hashmaps for better performance
- Standardized CLI error messages with consistent format

## [0.23.0] - 2026-07-27

### Added
- JSON Schema output now properly parses IN list CHECK constraints to `enum` values
- JSON Schema output handles NULL defaults (emits `null`) and boolean defaults (emits `true`/`false`)
- Diff output now shows type changes for modified columns (e.g., `~ field (modify: int → varchar)`)

## [0.22.0] - 2026-07-27

### Added
- Version number in generated SQL header comments (`-- Generated by rune 0.22.0`)
- JSON Schema output now includes CHECK constraint metadata (`minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`)
- JSON Schema output now includes `default` values for columns with defaults

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
