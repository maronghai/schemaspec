# Changelog

All notable changes to Rune will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

## [0.239.0] - 2026-08-11

### Added
- **SQL keyword formatting** — The `.ss` formatter now uppercases SQL keywords (CREATE, TABLE, SELECT, PRIMARY, KEY, etc.) inside `@if`/`@endif` conditional blocks. Rune type symbols (int, text, varchar) remain lowercase to preserve compatibility with the Rune type system.
- **WASM module tests** — 25 new unit tests for `wasm/common.zig` covering `classifyError` (all 6 error categories), `storeError`/`clearError` lifecycle, `containsSubstring`, `parseOption`, `parseDialectOption`, and `parseDiffFormatOption`.
- **Version utilities** — Added `formatAlloc()` for allocating formatted version strings and `writeMajorMinor()` for writing "major.minor" format to a writer.

### Changed
- Test count increased from 1,715+ to 1,752+.

## [0.218.0] - 2026-08-10

### Changed
- **Pipeline decomposition** — Extracted migrate handler from `pipeline/diff.zig` into `pipeline/migrate.zig`. `diff.zig` now contains only diff-related code (`DiffConfig`, `handleDiff`, `prepareDiff`, `prepareDiffFromSql`, `emitTraceAndStats`). `migrate.zig` contains migrate-related code (`MigrateConfig`, `handleMigrate`, `handleMigrateStatus`, `filterIncrementalChanges`, `collectMigrateFiles`, `findNextSequenceNumber`, `formatMigrationFileName`). Single-responsibility: diff owns diff computation and display; migrate owns migration SQL generation and file management.
- **`tune.zig` allocator fix** — Replaced hardcoded `std.heap.page_allocator` in `findBestFieldSet` with the passed-in allocator parameter, consistent with project conventions.

### Fixed
- **`tune.zig` documentation** — Added descriptive comments to `handleTune` branches explaining dry_run vs normal mode behavior.

## [0.194.0] - 2026-08-10

### Added
- **`tune.zig` unit tests** — 5 new tests for the tune command: template extraction from common fields, early return for single tables, no-op when no common fields, and helper function tests (`fieldName`, `tableName`).
- **`validate_views.zig` test integration** — Added missing import to `tests.zig` so the `validate_views` semantic pass tests are discovered by `zig build test`.

### Changed
- **Documentation sync** — Updated test counts across all documentation to reflect actual state (93 colocated files, 1,438+ tests). Added missing `resolve_conditionals` pass to `DEFAULT_PASSES` in ARCHITECTURE.md. Fixed leaf module path (`diagnostic.zig` → `diagnostic/format.zig`).
- **Type system docs** — Added Db2 and MSSQL dialect behavior sections to `type.md` (UUID handling, auto-increment, comment syntax, unsigned support).

## [0.180.0] - 2026-08-09

### Added
- **`index-column-missing` lint rule** — Warns when an index references columns that don't exist in the table. Catches typos and schema drift in index definitions.
- **`naming-prefix` lint rule** — Warns about table names using anti-pattern prefixes (`tbl_`, `t_`, `tb_`, `table_`). Helps enforce clean naming conventions.

### Changed
- **Improved `toCamelSingular` pluralization** — Handles irregular plurals (men→man, women→woman, children→child, people→person, data→datum), -ies→-y (categories→category, companies→company), doubled consonants (quizzes→quiz, addresses→address), and -ves (knives→knife, lives→life). Was previously limited to naive trailing-'s' strip.

## [0.162.0] - 2026-08-08

### Changed
- **Pipeline split** — Extracted output handlers from `pipeline/forward.zig` (520 lines) into `pipeline/handlers.zig` (270 lines). `forward.zig` now focuses solely on the compilation pipeline (tokenizer → parser → semantic → ResolvedAst). CLI-level handlers (`handleCompileRequest`, `handleValidate`, `handleCheck`, `handleStats`, `generateFromSchema`, `generateFromSchemaBatch`) live in `handlers.zig`.
- **Index validation optimization** — Replaced O(n²) linear column lookups in `validate_indexes.zig` with O(n) StringHashMap lookups for `checkColumnRefs`.

### Added
- **Handler tests** — New `pipeline/handlers_test.zig` with tests for `formatValidateResult` (valid/invalid JSON output).

## [0.151.0] - 2026-08-07

### Added
- **TextMate grammar for `.ss`** — Syntax highlighting for Rune schema files. Based on the formal EBNF grammar. Scopes for declarations (`$`, `~`, `%`, `#`, `&`, `>`, `@`, `!`), type symbols, modifiers, literals, and comments.
- **VS Code extension** — `packaging/vscode/` with language configuration, TextMate grammar, and commands (`Rune: Validate`, `Rune: Generate SQL`, `Rune: Initialize Schema`). Activation on `.ss` file open.
- **Language configuration** — Bracket matching, auto-closing pairs, folding markers, and comment toggling for `.ss` files.

### Changed
- **npm package version sync** — `packaging/npm/package.json` version aligned with VERSION file.

## [0.143.0] - 2026-08-06

### Added
- **WASM cross-compilation** — New `wasm32-wasi` build target. New `src/wasm.zig` entry point exports `rune_compile`, `rune_version`, `rune_reset` for browser/Deno usage. `wasm/rune.js` JavaScript wrapper provides `compile()` and `version()` APIs.
- **Windows CI** — New `test-windows` job runs unit tests and build validation on `windows-latest`.
- **ARM64 CI enhancement** — ARM64 test job now also runs PostgreSQL golden tests.
- **Release WASM builds** — Release workflow now includes `wasm32-wasi` target and packages as `rune-wasm32-wasi.tar.gz`.

### Changed
- **Conditional parallel compilation** — `codegen/parallel.zig` gracefully falls back to sequential streaming on WASM (no threads). `io.zig` mmap falls back to heap allocation on WASM (same as Windows).

## [0.105.0] - 2026-08-04

### Added
- **`rune init -d/--dialect`** — `rune init` now accepts `-d`/`--dialect` to specify target SQL dialect. Generated starter schema includes a dialect hint comment.
- **Config validation** — `rune.toml` values are now validated: `[dialect] default` must be a valid dialect name, `[output] color` must be `auto`, `always`, or `never`.

### Fixed
- **Version sync** — Fixed version drift between `version.zig` (0.103.0) and `VERSION` file (0.104.0). Both now report 0.105.0.
- **Improved error messages** — `FileNotFound` errors now show the specific file path that was not found.
- **Removed last `orelse unreachable`** — `dialect/dialect.zig:293` comptime block now uses explicit null check.

### Refactored
- **Deduplicated `ColorMode`** — Removed duplicate `ColorMode` enum from `cli.zig`. Now re-exports `color.ColorMode`.

## [0.91.0] - 2026-08-03

### Removed
- **Dead `DialectCapability` code** — Removed the `DialectCapability` struct (12 boolean feature flags) from `dialect.zig` and the `capability` field from `DialectBackend`. The flags were populated by all 6 backends but never read in production code. Eliminates ~100 lines of dead infrastructure.

### Refactored
- **Split `generators/common.zig`** — Extracted `DefaultFormatter` + `writeFormattedDefault` + ORM callbacks into `generators/common_defaults.zig` (used by drizzle/knex/sqlalchemy/typeorm). Extracted CHECK constraint parsers (`parseRange`, `parseComparison`, `parseInList`) into `generators/common_check.zig` (used by json_schema/openapi). `common.zig` re-exports all symbols for backward compatibility. Net reduction: clearer module boundaries with zero import changes for downstream generators.
- **Table-driven parameterized type matching** — Replaced 8 repetitive pattern-matching blocks in `reverse/map.zig` (int, decimal, numeric, varchar, character varying, varchar2, nvarchar2) with a table-driven `PARAM_PATTERNS` array and shared `matchParam` function. `NUMBER(P,S)` gets special handling for the "N" prefix. Net reduction: ~50 lines of duplicated pattern-matching code.
- **Comptime pass dependency validation** — Added comptime validation in `semantic/pass_manager.zig` that checks all dependency names in `DEFAULT_PASSES` exist as pass names. Catches typos and missing passes at compile time instead of runtime.

### Changed
- **`docs` command comment** — Added clarifying comment that `.docs` is a shortcut for `rune generate docs`, both routing through the generator registry.

## [0.90.0] - 2026-08-03

### Fixed
- **Version-resilient golden tests** — OpenAPI, GraphQL, and JSON Schema test scripts now use `compare_files()`/`diff_versions()` from `lib.sh` instead of raw `diff -u`. Golden tests no longer break on version bumps.
- **parse_typedef dialect support** — `parseDialect()` now handles all 6 SQL dialects (added mssql/sqlserver, oracle, db2). Custom type dialect overrides for these backends were previously silently dropped.

### Added
- **generator_test.zig** — 5 unit tests for the generator registry (count, lookup, unknown names, non-empty fields, name uniqueness).

### Changed
- Formatted 4 files with `zig fmt` (completions_test.zig, diff/engine_test.zig, pipeline/stats_test.zig, reverse/map.zig).

## [0.81.0] - 2026-08-02

### Added
- **`rune stats --json-errors`** — Machine-readable JSON output for schema statistics. Useful for CI/CD pipelines and tooling integration. Outputs a single JSON object with tables, fields, not_null, numeric, string, datetime, boolean, other, and views counts.
- **`rune bench --list`** — Show available benchmark stages (tokenize, parse, semantic, type_resolve, codegen) and modes (save, check, diff).
- **`formatStatsJson` unit tests** — 2 new tests for JSON stats formatting (zero values, populated values).

### Changed
- **Simplified main.zig error dispatch** — Flattened nested `switch(err)` into a single-level switch with all error variants. Removes redundant inner switch block.
- `handleStats` now accepts a `json_output: bool` parameter to control output format.

## [0.61.0] - 2026-08-01

### Added
- **View UNION/UNION ALL/INTERSECT/EXCEPT support** — Views now support set operations. Parser detects UNION keywords in view queries and splits them into structured AST fields (`union_op`, `second_query`). Codegen emits the combined query. Diff engine properly compares union views via `viewQueriesEql()`. Docs generator shows the full query including set operations.
- **`rune stats` command** — New subcommand that prints detailed schema statistics including field type breakdown: non-null count, numeric, string, datetime, boolean, and other types.
- **PostgreSQL type expansion** — Added `xml`, `cidr`, `macaddr` as passthrough types in `REVERSE_MAP`. These PostgreSQL-specific types are now properly recognized during reverse engineering and emitted as-is in `.ss` output.
- **Reverse engineering JSON output** (`rune reverse --format json`) — Reverse command now supports `--format json` to output structured JSON with table names, column definitions (name, type, primary_key, auto_increment, nullable, default), indexes, and foreign keys.

### Changed
- `View` AST type now has `union_op: ?ViewUnionOp` and `second_query: ?[]const u8` fields (both optional, default null)
- `TypedView` carries union fields through type resolution
- `parse_table.zig` detects set operation keywords at the top level (outside quotes)
- `codegen.zig` recombines query parts when emitting CREATE VIEW for union views
- `diff/engine.zig` uses `viewQueriesEql()` for structural view comparison
- `docs.zig` shows full query including union parts
- `grammar.ebnf` updated with set operator syntax
- `schema.md` updated with union view examples
- `type.md` updated with PG passthrough types

## [0.53.0] - 2026-07-30

### Changed
- **Shared default value formatting** — extracted `writeDefault` from 4 ORM generators (drizzle, knex, typeorm, sqlalchemy) into `generators/common.zig` with `DefaultFormatter` callback struct. ~120 lines of duplicated parsing logic consolidated into a single shared function.

### Added
- 22 new unit tests: `parse_recovery_test.zig` (16), `import_resolver_test.zig` (6)

### Fixed
- Replaced unsafe `@intFromPtr` pointer arithmetic in `parse_field.zig` with safe `std.mem.indexOf`

## [0.50.0] - 2026-07-30

### Changed
- **`ReverseMapping` struct refactored** — per-dialect named fields (`mysql`, `pg`, `sqlite`) replaced with `DialectTypeMap` struct. Adding a new dialect no longer requires editing every `REVERSE_MAP` entry.
- **`json_schema.zig` relocated** — moved from `src/` root to `generators/json_schema.zig` for consistent project structure.

### Added
- **`generators/common.zig`** — shared generator utilities: `hasEnumColumns()`, `findFkForColumn()`, `writeEnumValuesJoin()`, `tableHasNonPkIndexes()`, `tableHasCompositeFks()`.
- `DialectTypeMap` struct in `types/reverse_map.zig` — extensible dialect-indexed type mapping.

## [0.38.0] - 2026-07-28

### Fixed
- **`ast_visitor_test.zig` broken callbacks**: Test defined no-op `countVisitSchema`/`countVisitTemplate`/`countVisitSqlComment` callbacks but expected counters to increment, causing 24 test failures + 3 crashes + 592 memory leaks. Fixed callbacks to actually increment counters and added proper memory cleanup with `defer alloc.free()`.
- **FK rename buffer overflow**: `diff/fks.zig:adjustFkForRenames` used fixed-size `[8][]const u8` stack buffers. FKs with >8 fields would silently overflow. Replaced with allocator-based dynamic arrays (`AdjustedFk` struct with proper cleanup via `deinit()`).
- **`diffFks` memory leak**: `old_matched` and `new_matched` ArrayLists were never freed. Added `defer` cleanup.
- **PG ALTER TABLE index emission**: `pgEmitAlterAddIndex` emitted a comment (`-- NOTE: CREATE INDEX needed`) for regular indexes instead of actual SQL. Now emits standalone `CREATE INDEX` statement, closing the ALTER TABLE and reopening it for subsequent operations.
- **FK constraint name separator**: `mysqlEmitAlterDropFk` and `pgEmitAlterDropFk` concatenated field names without separator (e.g., `fk_user_idorg_id`). Now adds `_` separator (e.g., `fk_user_id_org_id`).

### Changed
- Updated golden test files for version 0.38.0.

## [0.37.0] - 2026-07-28

### Fixed
- **Broken colocated test compilation**: Fixed `parser/sql_parser_test.zig` incorrect import path (`parser/sql_parser.zig` → `sql_parser.zig`). Fixed redundant import paths in `diff/migrate_test.zig` and `semantic/template_test.zig`.
- **72 compilation errors across colocated tests**: Fixed API mismatches from v0.36.1 test extraction — function signature changes (`visitField` callback), missing struct fields (`line_no`, `view_diffs`, `line_type`), non-public function access (`mysqlRenderType`), `ModifierKind` → `ModifierType` rename, `ArrayList` API changes (`init` → `initCapacity`, `toOwnedSlice`), `BufSet` initialization, const/mutable slice mismatches, and `SchemaDiff` struct field additions.
- **`pass_manager.zig` runtime functions**: Fixed `detectConflicts()` and `transitiveDependsOn()` to use `ArrayList` instead of comptime slice concatenation; fixed `BufSet` initialization for Zig 0.16.
- **`type_registry.zig` API**: Fixed `toOwnedSlice` call to match Zig 0.16 API (no allocator argument).

### Added
- **`--json-errors` flag**: Output diagnostics as JSON array when compilation errors occur. Useful for CI/CD integration, editor plugins, and programmatic consumption. Each diagnostic includes `severity`, `line`, `col`, `file`, `message`, and optional `expected`/`actual` fields.
- **`check` subcommand**: `rune check [input.ss]` — standalone subcommand for schema validation. Equivalent to `rune --check` but more discoverable for CI/CD workflows.

### Changed
- Updated golden test files for version 0.37.0.

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
