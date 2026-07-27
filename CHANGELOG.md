# Changelog

All notable changes to this project will be documented in this file.

## [0.31.0] - 2026-07-27

### Architecture
- **PassAccess runtime enforcement**: Added `detectConflicts()`, `getParallelGroups()`, `transitiveDependsOn()` to `pass_manager.zig`. Added `--verbose-passes` CLI flag that prints semantic pass execution details (table counts before/after each pass).
- **DialectBackend optional method validation**: Added `validateOptionalMethods()` comptime check for 7 optional vtable methods (`emitCreateDatabase`, `emitUnsigned`, `emitAutoIncrement`, `emitTypeMetadata`, `emitConfidenceComment`, `reverseLookup`, `emitGeneratedColumn`). Non-null optional methods are now verified to be valid function pointers at compile time.
- **Reverse engineering confidence systematization**: Added `confidence_base` field (0-100) to all 46 `REVERSE_MAP` entries in `map_data.zig`. Core canonical symbols: 100, dialect variants: 80-95, passthrough types: 70.

### Features
- **SARIF diff output**: Added `--format sarif` for diff command — outputs Static Analysis Results Interchange Format for CI/CD integration. Includes `ruleId`, `level`, `message`, and `locations` for each change.
- **`--check` flag for diff/migrate**: Exit with code 1 if schema has differences. Useful for CI gates.
- **`rune docs` command**: New `docs` subcommand generates Markdown schema documentation from `.ss` files. Includes table listings, field descriptions (type, modifiers, defaults), FK relationship diagrams, and index details.
- **Import search paths**: Added `--import-path` CLI flag for specifying additional `@import` search directories. Supports `@import "std:path"` syntax for standard library imports.
- **LSP diagnostic format**: Added `formatLsp()` method to `DiagnosticCollector` — outputs diagnostics in LSP `Diagnostic` format with `range`, `severity`, `message`, and `source` fields.

### Testing
- **Reverse confidence tests**: Added `tests/test_reverse_confidence.sh` with 4 test cases: MySQL high-confidence types, SQLite ambiguous types, PostgreSQL-specific types, roundtrip field count verification.
- **Test coverage runner**: Added `tests/test_coverage.sh` — runs all 13 test suites and reports a pass/fail summary.
- **Golden file version sync**: Updated 247 golden files from version 0.22.0/0.29.0 to 0.31.0.

## [0.30.0] - 2026-07-27

### Architecture
- **DialectBackend vtable reorganization**: Split into 6 logical sections (Shared/Forward/Alter/TypeMapping/Optional/Behavioral) with clear SECTION comments. Updated `validateBackend` to validate methods by section.
- **PassContext read/write isolation**: Added `PassAccess` struct with `reads_tables`, `writes_tables`, `modifies_table_list`, `writes_types` fields. Added `canRunConcurrently()` function to detect if two passes can run in parallel. Added 4 unit tests for concurrency detection.
- **Import parse cache**: Added `ImportCache` memoization (`StringHashMap(CachedImport)`) in `pipeline/forward.zig`. Imported files are now cached to avoid re-parsing when the same file is imported by multiple parents.

### Bug Fixes
- **Fix `undefined` io parameter**: Changed `compileInternal` in `pipeline/forward.zig` to accept `?std.Io` instead of `std.Io`. Callers now pass `null` when imports are disabled, preventing potential crashes from undefined behavior.
- **Fix DiagnosticCollector double-printing**: `record()` now aliases `push()` instead of calling `printDiagnostic()` + `push()`. This eliminates duplicate diagnostic output when callers also use `printAll()`.
- **Fix CLI `-o` flag with stdin**: When using `rune -o output.sql` (no input file), the `-o` flag was not being parsed correctly. The compiler now detects when the first positional arg starts with `-` and treats it as the default compile command from stdin.

### Code Quality
- **Extract `emitTraceAndStats` helper**: Deduplicated 4 identical trace/stats blocks in `pipeline/diff.zig` into a single helper function.
- **DialectBackend vtable reorganized**: Methods grouped into Shared (4), Forward (11), Alter (9), TypeMapping (2), Optional (7), Behavioral (3) sections with clear documentation.

### Testing
- **Import system tests**: Added `tests/test_imports.sh` with 6 test cases: basic import, template import, nested imports (A→B→C), circular import detection, missing file detection, and dialect-specific imports.
- **Stdin pipeline tests**: Added `tests/test_stdin.sh` with 4 test cases: basic stdin, stdin with dialect flag, stdin with output flag, stdin with check mode.
- **Benchmark regression test**: Added `tests/test_bench.sh` with `--save` and `--check` modes. Compares current build performance against saved baseline with 20% regression threshold.
- **JSON Schema golden tests**: Added 2 new test files (`json-schema-fk.ss`, `json-schema-template.ss`) with corresponding golden files for FK/enum and template inheritance scenarios.
- **Pass manager unit tests**: Added 4 tests for `canRunConcurrently()`: independent passes, dependent passes, write-write conflict, and read-write compatibility.

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

### Features
- **`--stats` / `-s` flag**: Print compilation statistics (table/field/view counts) to stderr after compilation
- **`--check` flag**: Dry-run mode — validate schema without writing output, prints "schema is valid" on success
- **`--quiet` / `-q` flag**: Suppress non-essential output (e.g. "Written to ..." messages)

### Testing
- Add 11 unit tests for new CLI flags (--stats, -s, --quiet, -q, --check, diff --stats, migrate --stats, reverse --stats)
- All unit tests pass
- All golden tests pass: MySQL (86), PostgreSQL (84), SQLite (25), Migration (34), Diff (12), Reverse (15), Error Recovery (12), JSON Schema (1), Roundtrip (20)

## [0.13.0] - 2026-07-27

### Code Quality
- **Extract `splitLines` helper in `pipeline/forward.zig`**: Deduplicate 3 identical line-splitting blocks (compilePipeline, compilePipelineWithImports, parseOnly) into a shared helper function
- **Convert `TypeResolver` from struct to namespace**: TypeResolver was a struct that only held an allocator — now uses namespace functions (`TypeResolver.resolve(alloc, ...)`, `TypeResolver.resolveColumn(alloc, ...)`) eliminating `init` boilerplate across 11 call sites
- **Hoist `TypeResolver` out of loops in `diff/migrate.zig`**: Rollback functions no longer create `TypeResolver.init(alloc)` inside loops; direct namespace calls eliminate per-iteration allocation overhead
- **Remove redundant `tr` parameter from `emitTableDiffs`/`emitFieldDiffs`**: These functions now call `TypeResolver.resolve`/`resolveColumn` directly instead of receiving a pre-initialized instance

### Testing
- Add 16 unit tests for `cli.zig` argument parsing: version flags, dialect selection, subcommand routing, error cases (unknown dialect, missing args), flag parsing (-o, -t, -T, --rollback)
- All unit tests pass
- All golden tests pass: MySQL (86), PostgreSQL (84), SQLite (25), Migration (34), Diff (12), Reverse (15), Error Recovery (12), JSON Schema (1), Roundtrip (20)

## [0.12.0] - 2026-07-27

### Code Quality
- **Consolidate pipeline handlers**: Extract shared `traceWithTyped` and `traceForward` helpers, reducing 4 near-identical `handleCompile*` functions from ~20 lines each to ~8 lines each (net -48 lines)
- **Remove unused `std.Io` parameter from `compilePipeline`**: The parameter was immediately discarded (`_: std.Io`); all callers updated
- **Fix hardcoded MySQL dialect in rollback view diffs**: `emitRollbackViewDiffs` in `diff/migrate.zig` now receives the actual dialect parameter instead of hardcoding `.mysql`
- **Improve `parseOnly` error handling**: Parse errors in imported files now propagate diagnostics (matching `compilePipelineWithImports` pattern) instead of silently swallowing errors
- **Extract `computeBaseDir` in `compileFile`**: Reuse existing helper instead of duplicating path-separator logic inline

### Testing
- All unit tests pass
- All golden tests pass: MySQL (86), PostgreSQL (84), SQLite (25), Migration (34)

## [0.11.0] - 2026-07-26

### Features
- **Schema import/include**: Add `@import("other.ss")` syntax for multi-file schema composition. Supports relative path resolution, circular dependency detection (max depth 8), and nested imports. Imported templates and tables are merged into the current schema namespace.
- **Migration rollback**: Add `--rollback` flag to `migrate` subcommand. Generates inverse SQL operations (CREATE→DROP, ADD COLUMN→DROP COLUMN, etc.) for reverting migrations. Handles tables, views, indexes, and foreign keys.

### Architecture
- **Pipeline-level import handling**: `@import` directives are processed at the pipeline level before tokenization, using recursive `parseOnly` for imported files (no semantic analysis on imports).
- **New `compileFile` API**: `pipeline/forward.zig` adds `compileFile` for path-based compilation with import resolution, used by `handleCompileFile` and `handleCompileJsonSchemaFile`.

### Testing
- Add unit tests for parser sub-modules: `parse_fk.zig` (8 tests), `parse_check.zig` (11 tests), `parse_index.zig` (9 tests), `parse_table.zig` (10 tests)
- Add reverse engineering tests for generated columns across all 3 dialects (MySQL, PostgreSQL, SQLite)
- Add golden test files for schema import (simple table import, template import, nested imports)

### Documentation
- Update VERSION to 0.11.0

## [0.10.0] - 2026-07-26

### Features
- **Virtual/Generated columns**: Support `col AS (expr) VIRTUAL` and `col AS (expr) STORED` syntax for computed columns. Also supports `GENERATED ALWAYS AS (expr)` variant. MySQL: VIRTUAL and STORED. PostgreSQL: STORED only (VIRTUAL falls back to STORED). SQLite: both supported (3.31.0+).
- **Comptime dialect validation**: Added compile-time validation that all required DialectBackend vtable methods are implemented for each dialect backend.

### Architecture
- **Split diff/migrate.zig**: Extracted `generateMigrationJson` into separate `diff/migrate_json.zig` module for better separation of concerns (JSON migration vs SQL migration).
- **Remove leaky re-export**: Removed `TypeResolver` re-export from `typed_ast.zig`; all consumers now import directly from `type_resolver.zig`.

### Testing
- Add unit tests for `codegen/indexes.zig` — inline indexes, standalone indexes, dominance checks, cross-dialect differences (6 tests)
- Add unit tests for `parser/parse_field.zig` and `parser/parse_template.zig` — type parsing, fused modifiers, standalone modifiers, template headers, slot detection (20+ tests)
- Add golden tests for generated columns across all 3 dialects (MySQL, PostgreSQL, SQLite)
- Fix `test_json_schema.sh` — remove fragile `trap` inside loop, tests now properly report failures

### Documentation
- Update CHANGELOG.md with 0.10.0 entry
- Update VERSION file to 0.10.0

## [0.9.1] - 2026-07-26

### Features
- Add `validate` subcommand — standalone schema validation without SQL output (CI/CD use case). Reports diagnostics and exits with code 1 on errors.
- Implement proper migration JSON output for `migrate --target json-schema` — produces structured `operations` array with typed entries (`drop_table`, `create_table`, `add_column`, `drop_column`, `modify_column`, `rename_column`, `add_index`, `drop_index`, `add_fk`, `drop_fk`, `create_view`, `drop_view`, `modify_view`, `alter_metadata`) plus `dialect` and `wrapped_in_transaction` metadata.

### Bug Fixes
- Fix VERSION file sync — was 0.8.3 while main.zig was 0.9.0; both now 0.9.1

### Code Quality
- Remove `handleMigrateDiffJson` TODO — migration JSON now produces proper migration structure instead of diff JSON

### Documentation
- Update README.md with `validate` subcommand and migration JSON output documentation

## [0.9.0] - 2026-07-26

### Bug Fixes
- Fix `auto_inc_pk` vs `auto_inc` diagnostic string in `validate_type_modifiers.zig` — both branches previously produced `"auto_increment"`, now `.auto_inc_pk` correctly produces `"auto_increment_primary_key"`
- Rename `handleMigrateJson` → `handleMigrateDiffJson` in `pipeline/diff.zig` — was producing diff JSON (same as `handleDiffJson`) instead of migration JSON; added TODO for proper migration JSON output

### Dead Code Removal
- Remove unused `type_map` import from `types/typed_ast.zig`
- Remove unused `reverse_map` import from `reverse/codegen.zig`
- Remove unused `TypeInfo`, `IndexDecl`, `FkDecl` type aliases from `diff/engine.zig`
- Remove unused `Modifier` import from `diff/fields.zig`
- Remove duplicate `ast` alias from `semantic/analyzer.zig` (line 10, `Ast` on line 11 is the used one)
- Remove dead `is_parameterized` field from `ReverseResult` in `dialect/dialect.zig`
- Remove dead `has_changes` tracking variable from `diff/format.zig` (set but never read)
- Remove dead `generateSingleTypedTable` and `generateCheckExpr` functions from `codegen/codegen.zig`, plus unused `ast_mod` and `CheckConstraint` imports

### Code Quality
- Add module-level `io_mod` import in `pipeline/diff.zig` — replaces 4 inline `@import("../io.zig")` calls, consistent with `forward.zig` and `reverse.zig`

### Testing
- Add 6 unit tests for `semantic/pass/suffix_inference.zig` — previously the only semantic pass with zero unit tests (`_id`→int, `_at`→datetime, `_on`→date, short name→varchar, explicit type preserved, multiple fields)

## [0.8.3] - 2026-07-26

### Bug Fixes
- Fix buffer overflow in `reverse/map.zig`: add bounds check for `character varying(N)` and `varchar(N)` handlers when N exceeds 15 digits

### Dead Code Removal
- Remove unused `input_name` parameter from `handleCompile` and `handleCompileJsonSchema` in `pipeline/forward.zig`
- Remove unreachable `FkForm::ultra` variant from `reverse/fk.zig` and its dead branch in `reverse/codegen.zig`
- Remove dead `findNextSyncPoint` function and `SyncPoint` enum from `parse_recovery.zig` (never wired into parser)
- Remove unused `FkActionType`, `FkActionTrigger`, and `FkAction` imports from `reverse/sql_to_resolved.zig`
- Remove unused `diff_format` import from `diff/engine.zig`

### Type Deduplication
- Move canonical `FieldDiff`, `IndexDiff`, `FkDiff` definitions to `diff/types.zig` — single source of truth for all diff data types
- Remove `SqlType` re-exports from `types/typed_ast.zig` and `types/type_map.zig` — consumers now import directly from `types/sql_type.zig`
- Remove `formatDiff`/`printDiff` re-exports from `diff/engine.zig`

### Testing
- Add inline unit tests for `diff/fields.zig`: `fieldSignatureMatch`, `diffFields` rename detection, `checkEqual`
- Add inline unit tests for `diff/format.zig`: `writeDiffTo` and `formatDiffJson` output validation

## [0.8.2] - 2026-07-26

### Code Quality
- Fix silent error swallowing in `DiagnosticCollector.push()` — allocation failures now log a warning instead of being silently ignored
- Extract duplicate `makeTestFieldWithMods()` test helper to `semantic/test_helpers.zig` — centralized test utility
- Add doc comments for magic numbers: recursion depth limit 32 in `type_resolver.zig`, template max formula in `template_extraction.zig`

## [0.7.4] - 2026-07-26

### Code Quality
- Consolidate duplicated `lookupSym` switch statements (mysql.zig, pg.zig, sqlite.zig) into data-driven table in `common.zig` — `DEFAULT_SYM_MAP` (15 shared entries) + `SQLITE_SYM_MAP` (3 overrides) with `lookupSymDefault` fallback scan
- Extract `stripCommentPrefix` helper to `common.zig` — removes duplicated `:` prefix stripping in pg.zig and sqlite.zig comment emitters
- Replace fragile string-parsing `codegen.diagnosticTrace` with structured `TypedAst` inspection — counts tables/columns/views/FKs/indexes directly from the IR instead of regex-like SQL line matching

## [0.7.3] - 2026-07-26

### Code Quality
- Remove duplicated `findResolvedTable` and `findTypedView` from `diff/migrate.zig` — now reuse public versions from `diff/emit.zig`
- Extract shared pipeline initialization (`parseFile`) in `bench.zig` — eliminates duplication between `runPipelineTimed` and `runPipeline`
- Unify terminal diagnostic formatting — `printDiagnostic` and `DiagnosticCollector.formatTerminal` now share `formatDiagnosticTo` core logic

## [0.7.2] - 2026-07-26

### Code Quality
- Remove wrapper functions in `diff/migrate.zig` — `emitComma`, `beginAlterTable`, `findResolvedTable`, `findTypedView` now called directly from `emit.zig`, reducing indirection

## [0.7.1] - 2026-07-26

### Code Quality
- Reuse TypeResolver + Codegen instances across table diffs in `diff/migrate.zig` — eliminates per-table allocation overhead by threading shared instances through `emitTableDiffs` → `emitFieldDiffs`
- Extract `detectSqlDialect` from `pipeline/reverse.zig` to `reverse/dialect_detect.zig` — better separation of concerns, detection logic now lives alongside other reverse pipeline modules

### Testing
- Add 4 unit tests for `diff/engine.zig` core scenarios: dropping tables, modifying fields, creating views, identical views

## [0.7.0] - 2026-07-26

### Code Quality
- Extract `diff/emit.zig` — shared helpers (`beginAlterTable`, `emitComma`, `findResolvedTable`, `findTypedView`) used by both `migrate.zig` and `format.zig`
- Deduplicate trace blocks in `pipeline/diff.zig` — extracted `DiffResult` named struct and `traceDiffResult` helper, reducing 4 identical trace blocks to 1
- Add `jsonEscapeString` utility to `utils.zig` — escapes `"`, `\`, `\n`, `\r`, `\t`, and control characters; applied in `formatDiffJson` to prevent invalid JSON output
- Decompose `resolveColumnInner` in `type_resolver.zig` — extracted `ModifierFlags` struct, `classifyModifiers()` and `buildSymType()` helpers

### Error Handling
- Add `max_errors: usize = 100` threshold to `DiagnosticCollector` — stops recording errors when exceeded, emits "too many errors" message

### Semantic Validation
- Add duplicate composite index detection in `validate_indexes.zig` — warns when two indexes have identical field lists, kind, and descending flags but different names

### Testing
- Add 2 unit tests for `DiagnosticCollector.max_errors` behavior
- Add 4 unit tests for `validate_type_modifiers.zig` (unsigned on numeric/string, auto_inc on non-numeric, empty modifiers)
- Add 1 unit test for duplicate composite index detection
- Add 11 unit tests for `type_resolver.zig` (classifyModifiers, buildSymType)

## [0.6.9] - 2026-07-25

### Features
- Add `--target json` output mode for `rune diff` and `rune migrate` — produces structured JSON for programmatic consumption
- Add `--trace` flag to `rune diff`, `rune migrate`, and `rune reverse` — prints intermediate IR (ResolvedAst, SchemaDiff, SqlSchema) for debugging

### Bug Fixes
- Fix stale VERSION constant in main.zig ("0.4.63" → "0.6.9")

### Code Quality
- Expand reverse pipeline dialect detection with 14 new patterns and weighted confidence scoring (ENGINE=, ROW_FORMAT=, UNIQUE KEY for MySQL; SERIAL, BIGSERIAL, bytea, jsonb, timestamptz for PG; ON CONFLICT for SQLite)
- Add cross-table duplicate name validation in `validate_schema.zig` — emits error when two tables share the same name
- Add trace helpers to diff/migrate/reverse pipelines for intermediate IR inspection

### Testing
- Add `diff format json: produces valid JSON structure` unit test
- Add `validate_schema: duplicate table names emit diagnostic` unit test

## [0.6.8] - 2026-07-25

### Code Quality
- Extract `TypeInfo.eql` method to `types/ast.zig` as single source of truth for type equality
- Remove duplicated `symTypeSame` in `validate_template_types.zig` — now delegates to `TypeInfo.eql`
- Simplify `typeInfoEqual` in `diff/fields.zig` to delegate to `TypeInfo.eql`
- Extract `validateSelfRefFk` helper in `validate_schema.zig` to deduplicate self-referencing FK validation
- Pass pre-built field maps to `detectRenames` in `diff/fields.zig` to avoid redundant HashMap construction
- Remove unused `walkResolvedTablesMut` method from `ast_visitor.zig`
- Merge identical `noopInlineColumnCommentPG`/`noopInlineColumnCommentSQLite` into single `noopInlineColumnComment` in `dialect/common.zig`

## [0.6.7] - 2026-07-25

### Code Quality
- Merge duplicate `fieldsEqual`/`fieldSignatureMatch` functions in `diff/fields.zig`
- Remove redundant condition in `detectRenames` in `diff/fields.zig`
- Remove unused `table_name` parameter from `isInlineIndex`, `writeColumnModifiers`, `writeColumnSuffix` in `reverse/column.zig`
- Remove empty no-op branch in `diff/format.zig`
- Extract `prepareDiff` helper in `pipeline/diff.zig` to deduplicate diff/migrate logic

## [0.6.6]

- Previous releases (see git history)
