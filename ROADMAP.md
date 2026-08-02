# Rune Roadmap

This document outlines the planned evolution of Rune toward becoming a **universal database schema interchange format**. A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.81.0 (2026-08-02)

---

## Legend

- [ ] Planned — not yet started
- [x] Done — shipped in a release
- Priority is top-down within each phase; phases overlap in practice
- Version numbers are approximate — shipped when ready, not by deadline

---

## Phase 1: Core Solidification

Polish the existing foundation. Most items shipped in v0.38–v0.40.

### Parser & Error Recovery

- [x] Synchronized multi-error recovery — report all syntax errors in one pass instead of fail-fast
- [x] Partial schema compilation — emit valid SQL for correct tables even when others have errors

### Semantic Analysis (all done)

- [x] Cycle detection for template inheritance
- [x] FK target validation — error when inline FK references a non-existent table or column
- [x] Unused template warning
- [x] Duplicate column name detection within a table
- [x] "Did you mean?" suggestions — Levenshtein edit distance for misspelled references

### Testing

- [x] Fuzz testing infrastructure — random `.ss` input to find parser crashes
- [ ] Property-based tests for roundtrip fidelity (`.ss` → compile → reverse → compile → compare)
- [x] Golden test parallelization — `tests/test_parallel.sh` runs suites concurrently

---

## Phase 2: Extended Dialect Support

Add enterprise SQL dialects. Dialect infrastructure (capability flags) is done.

### New Dialect Backends

- [x] **Oracle** — `dialect/oracle.zig` (~300 lines). No `AUTO_INCREMENT` (sequences + triggers), `NUMBER` precision/scale, `VARCHAR2`/`NVARCHAR2`, `CLOB`/`NCLOB`, double-quote identifier quoting
- [x] **Microsoft SQL Server** — `dialect/mssql.zig` (~250 lines). `IDENTITY`, `NVARCHAR`/`NTEXT`, schema-qualified names (`dbo.table`), `GO` batch separators
- [x] **IBM Db2** — `dialect/db2.zig` (~250 lines). `GENERATED ALWAYS AS IDENTITY`, `BIGINT`/`INTEGER`/`SMALLINT`, `DECIMAL(p,s)`, `VARCHAR(n)`, `CLOB`/`BLOB`, double-quote identifier quoting, `COMMENT ON`, `GENERATED ALWAYS AS (expr) STORED`, `RENAME COLUMN`.

### Dialect Infrastructure (done)

- [x] Dialect capability flags — 12 feature flags per backend
- [x] Generator API dialect awareness
- [x] CLI unknown-flag detection

### Dialect Testing & Reverse

- [x] Dialect-specific test suites — `tests/test_oracle.sh`, `tests/test_mssql.sh`
- [x] `rune reverse --dialect oracle` — dialect-aware reverse engineering per backend

---

## Phase 3: ORM & API Schema Output

Bridge the gap between database schema and application code.

### ORM Generators

- [x] `rune generate prisma schema.ss`
- [x] `rune generate drizzle schema.ss`
- [x] `rune generate typeorm schema.ss` — TypeORM entity classes
- [x] `rune generate sqlalchemy schema.ss` — SQLAlchemy ORM models
- [x] `rune generate knex schema.ss` — Knex migration files

### API Schema

- [x] `rune generate openapi schema.ss` — OpenAPI 3.1 spec
- [x] `rune generate graphql schema.ss` — GraphQL type definitions
- [x] `rune generate json-schema schema.ss` — `$defs`, `$ref`, proper `required` arrays

### Generator Infrastructure (done)

- [x] `rune generate --list` — show available generators
- [x] Generator registry — pluggable `Generator` struct with `REGISTRY` array
- [x] SQL DDL generator
- [x] Markdown docs generator
- [ ] Generator plugin system — user-defined generators via Zig plugins or WASM modules
- [ ] Template overrides — `.rune-template` files for customizing generator output

---

## Phase 4: Incremental & Live Workflows

Move from batch compilation to interactive, incremental usage.

### Incremental Migration

- [ ] `rune migrate --incremental old.ss new.ss` — only emit SQL for changed tables
- [ ] Migration file naming — `001_add_users.sql`, `002_add_posts.sql` with auto-sequencing
- [ ] Migration dependency graph — detect and order dependent migrations
- [ ] `rune migrate status` — compare migration files against current schema state

### Live Schema Monitoring

- [ ] `rune watch schema.ss` — watch file changes and recompile automatically
- [ ] `rune diff --live schema.ss mysql://host/db` — compare `.ss` file against a live database
- [ ] Schema drift detection — compare expected vs actual database state

### CI/CD Integration

- [ ] GitHub Action — `rune-ci/check-schema` composite action
- [ ] GitLab CI template — `.rune-ci.yml` for pipeline integration
- [ ] Pre-commit hook generator — `rune hooks pre-commit` outputs shell scripts

---

## Phase 5: Developer Experience

Make Rune delightful to use day-to-day.

### LSP Language Server

- [ ] `rune-lsp` — standalone language server binary
- [ ] Completion — type symbols (`n`, `s32`, `m`), modifiers (`++`, `!`, `*`), keywords
- [ ] Diagnostics — real-time error/warning display
- [ ] Go-to-definition — navigate from FK reference to target table/column
- [ ] Hover — show SQL type equivalent for SS symbols
- [ ] Code actions — quick fixes for common errors
- [ ] Document symbols — outline view for tables, templates, views

### Editor Integration

- [ ] VS Code extension — syntax highlighting, completion, diagnostics
- [ ] Neovim plugin — LSP-based with Treesitter grammar
- [ ] JetBrains IDE plugin — IntelliJ-based schema editor

### CLI Improvements

- [x] `rune init` — scaffold a new project with example schema (v0.66.0)
- [ ] `rune playground` — web-based `.ss` editor with live compilation (WASM)
- [x] Shell completion scripts — `rune completions bash|zsh|fish|powershell` (v0.66.0)
- [x] `rune fmt` — auto-format `.ss` files (v0.68.0)
- [ ] Colored output — syntax-highlighted SQL and diff output

---

## Phase 6: Ecosystem & Community

Build the community and ecosystem around Rune.

### Distribution

- [ ] Package managers — `brew install rune`, `scoop install rune`, `apt`/`yum`
- [ ] npm package — `npx rune schema.ss`
- [ ] Docker image — `ghcr.io/rune-lang/rune:latest`
- [ ] Zig package manager — `build.zig.zon` for dependency consumption

### Documentation

- [ ] Interactive tutorial — web-based walkthrough with live examples
- [ ] Migration guide — from SQL DDL, Prisma, Knex to Rune `.ss`
- [ ] Cookbook — common patterns (multi-tenant, soft delete, audit trail)
- [ ] Video walkthroughs — schema design, migration, CI/CD integration

### Community

- [ ] RFC process — formal proposal mechanism for language changes
- [ ] Schema registry — shared template library
- [ ] Playground sharing — share `.ss` snippets via URL

---

## Architecture Targets

Ongoing improvements pursued alongside feature work.

### Performance

- [ ] Streaming compilation — output SQL as soon as each table is resolved
- [ ] Parallel table compilation — compile independent tables concurrently
- [ ] Memory-mapped file I/O — for large schema files (>10MB)
- [ ] Benchmark CI gate — enforce no regressions beyond 10% (currently 20%)
- [x] Benchmark dialect parameterization — `rune bench --dialect <d>` supports all 6 dialects (v0.74.0)

### Code Quality

- [x] Remove all `catch unreachable` in production code (v0.39.0)
- [ ] Zero-allocation codegen path — reuse buffers across compilations
- [ ] Audit all `@intCast` / `@enumFromInt` for safety in debug builds
- [ ] Formalize IR versioning — schema for forward/backward compatibility

### Platform

- [ ] Cross-compile to WASM — enable browser and Deno usage
- [ ] Windows native builds — test and document MSVC/MinGW paths
- [ ] ARM64 CI — test on Apple Silicon and ARM Linux

---

## Release History

### v0.81.0 (2026-08-02)

- **`rune stats --json-errors`** — Machine-readable JSON output for schema statistics. Outputs `{"tables":N,"fields":N,"not_null":N,"numeric":N,"string":N,"datetime":N,"boolean":N,"other":N,"views":N}`. Useful for CI/CD pipelines and tooling integration.
- **`rune bench --list`** — Show available benchmark stages (tokenize, parse, semantic, type_resolve, codegen) and modes (save, check, diff). Improves benchmark discoverability.
- **Simplified main.zig error dispatch** — Flattened nested `switch(err)` into a single-level switch with all error variants. Removes redundant inner switch block.
- **New unit tests** — 2 tests for `formatStatsJson` (zero values, populated values) in `pipeline/stats_test.zig`.

### v0.80.0 (2026-08-02)

- **Unified pipeline entry points** — Replaced three nearly-identical functions (`compilePipeline`, `compilePipelineVerbose`, `compilePipelineWithImports`) with a single `compilePipeline(alloc, file_data, opts)` that accepts a `PipelineOptions` struct. Reduces code duplication and makes pipeline behavior explicit via named fields. Net reduction: ~30 lines of duplicated wrapper code.
- **Fixed `std.process.exit` in library code** — `generateFromSchema` now returns `error.UnknownGenerator` instead of calling `std.process.exit(1)` directly. Error handling is now consistent — all errors propagate to `main.zig`'s error dispatch.
- **Fixed unsafe `@intCast`** — `PipelineResult.skipped_tables` now uses `@min` to safely clamp `error_count` to `u32` range, preventing potential panics on 64-bit systems with extremely large error counts.
- **Fixed formatter dead code** — Removed identical `if (in_block) / else` branches in `formatter.zig` that both appended `'\n'`.
- **Documented reserved parameter** — Added doc comment to `canonicalSimple` explaining the `dialect` parameter is reserved for future dialect-specific canonicalization.
- **Named constants for magic numbers** — Extracted `STDIN_BUFFER_SIZE`, `OUTPUT_BUFFER_SIZE`, `STDIN_PATH` in `io.zig`; `INITIAL_PADDING` in `formatter.zig`; `MAX_IMPORT_DEPTH` in `import_resolver.zig`. Error messages now reference constants instead of hardcoded values.
- **New unit tests** — Added `dialect/dialect_test.zig` (18 tests: getBackend, canOmitType, DialectCapability, behavioral flags, lookupSym, renderType), `pipeline/stats_test.zig` (4 tests: empty schema, table/field counting, not_null, views), `pipeline/reverse_test.zig` (1 test: ReverseConfig defaults).
- **`STDIN_PATH` constant** — Replaced 8 hardcoded `"-"` strings in `main.zig` with `io_mod.STDIN_PATH` for consistency.

### v0.79.0 (2026-08-02)

- **Consolidated remaining dialect duplication** — Extracted `common.emitAlterDropIndexNoQuote` for Oracle, MSSQL, and Db2 (3 identical implementations replaced with shared helper). Removed trivial pass-through `emitEnumTypeCheck` wrappers from Oracle and Db2 (vtable now points directly to `common.emitEnumTypeCheck`). Net reduction: ~15 lines of duplicated code.
- **Documentation sync** — Fixed stale module path references in ARCHITECTURE.md (`dialect_common.zig` → `dialect/common.zig`, `reverse_codegen.zig` → `reverse/codegen.zig`). Corrected vtable description from "23 core + 6 optional" to "26 required + 7 optional = 33 total function pointers". Updated PG/SQLite shared method count from "4/5" to "7". Fixed stale `type_map.zig` re-export claim in `sql_type.zig` and ARCHITECTURE.md. Fixed `sqlite_hints.zig` comment referencing non-existent `reverseLookupSqlite`.

### v0.78.0 (2026-08-02)

- **Consolidated dialect backend duplication** — Extracted 5 shared helpers into `dialect/common.zig`:
  - `renderTypeFromTable` — eliminates identical 4-line renderType functions across all 6 dialect backends
  - `emitTableCommentStandalone` — shared COMMENT ON TABLE for PG, Oracle, Db2 (was duplicated in each)
  - `emitColumnCommentStandalone` — shared COMMENT ON COLUMN for PG, Oracle, Db2 (was duplicated in each)
  - `emitCreateViewShared` — shared CREATE OR REPLACE VIEW for MySQL, PG, Oracle, Db2 (only quote function differs)
  - Oracle and Db2 now use existing `common.emitEnumTypeCheck` instead of local copies
- **New unit tests** — Added `diff/engine_test.zig` with 7 tests covering the core diff engine (empty schemas, added/dropped/modified tables, added/dropped/modified fields, mixed changes)
- Net reduction: ~80 lines of duplicated dialect code replaced with shared helpers

### v0.77.0 (2026-08-02)

- **Fixed duplicate detection patterns** — Removed duplicate `GENERATED ALWAYS AS (` and `DECFLOAT` checks in `reverse/dialect_detect.zig` that double-counted Db2 detection scores.
- **Fixed test_bench.sh cross-platform path** — Removed hardcoded Windows `.exe` suffix; now uses `lib.sh`'s `BIN_SUFFIX` variable for Linux/macOS/Windows compatibility.
- **Expanded test coverage runner** — Added OpenAPI and GraphQL test suites to `test_coverage.sh` (were present but not included in the full runner).
- **ROADMAP accuracy** — Marked `rune init` (v0.66.0), `rune completions` (v0.66.0), and `rune fmt` (v0.68.0) as done.

### v0.76.0 (2026-08-02)

- **Expanded Oracle reverse engineering tests** — 5 tests (was 3): multi-word types, GENERATED BY DEFAULT AS IDENTITY, identity options.
- **Expanded Db2 reverse engineering tests** — 5 tests (was 3): GENERATED ALWAYS AS IDENTITY, BOOLEAN, BIGINT/SMALLINT, DOUBLE PRECISION, DECIMAL.
- **Parser unit tests** — 5 new tests for multi-word types (TIMESTAMP WITH LOCAL TIME ZONE, DOUBLE PRECISION), Oracle identity options, and Db2 types.
- **bench.zig refactoring** — Extracted `BenchArgs` config struct, `parseBenchArgs` helper, `stagePairs` shared iteration, and `Baseline.total()` method. Improved readability and testability.

### v0.75.2 (2026-08-02)

- **Oracle dialect fixes** — Updated 103 golden files for corrected Oracle dialect output.

### v0.75.1 (2026-08-02)

- **SQL Parser enhancements** — Inline block comment parsing, Oracle identity options, multi-word type handling (TIMESTAMP WITH TIME ZONE, DOUBLE PRECISION, CHARACTER VARYING).
- **Reverse map expansion** — 52 new entries for Oracle and Db2 multi-word types.
- **Large schema test file** — 519-line comprehensive test schema with Chinese comments and complex templates.

### v0.75.0 (2026-08-02)

- **Pipeline config structs** — Added `DiffConfig`, `MigrateConfig`, and `ReverseConfig` structs to replace 8-11 positional parameters in pipeline handlers, following the existing `CompileConfig` pattern.
- **Unified diff/migrate handlers** — Merged 3 diff format handlers and 2 migrate format handlers into single functions that switch on `cfg.format`.
- **`generateFromSchema` helper** — Extracted compile→generate→write pattern from `main.zig` into `pipeline/forward.zig`, eliminating duplicate dispatch logic for `rune generate` and `rune docs`.

### v0.74.0 (2026-08-02)

- **Benchmark dialect parameterization** — `rune bench --dialect <d>` benchmarks any SQL dialect instead of hardcoding MySQL. Per-dialect baseline files enable cross-dialect performance comparison.
- **Dialect auto-detection for all 6 dialects** — `reverse/dialect_detect.zig` now detects MSSQL, Oracle, and Db2 DDL patterns, completing the reverse engineering story for all supported dialects.
- **CLI help text fix** — Added missing `db2` to the `-d` flag example.
- 12 new benchmark unit tests, 7 new dialect detection tests.

### v0.73.0 (2026-08-02)

- **Dialect-aware reverse engineering for Oracle and Db2** — `reverseLookup` now matches Oracle and Db2 type columns in `REVERSE_MAP`. Case-insensitive parameterized type matching (`VARCHAR2(N)`, `NUMBER(P,S)`, `DECIMAL(P,S)`) enables accurate reverse engineering of Oracle and Db2 DDL. 6 new golden tests across 2 new test suites.
- **Consolidated `emitAlterDropFk`** — Extracted FK name-joining logic from PG, MSSQL, Oracle into shared `common.emitAlterDropFkShared` / `common.emitAlterDropFkMssql` helpers. Each dialect's `emitAlterDropFk` is now a one-line call. MySQL and Db2 kept separate (use `DROP FOREIGN KEY` syntax instead of `DROP CONSTRAINT`).

- **Consolidated `emitAlterDropFk`** — Extracted FK name-joining logic from PG, MSSQL, Oracle into shared `common.emitAlterDropFkShared` / `common.emitAlterDropFkMssql` helpers. Each dialect's `emitAlterDropFk` is now a one-line call. MySQL and Db2 kept separate (use `DROP FOREIGN KEY` syntax instead of `DROP CONSTRAINT`).
- **Consolidated `emitAlterAddIndex`** — Extracted standalone CREATE INDEX logic from PG, Oracle, Db2, MSSQL into shared `common.emitAlterAddIndexStandalone` helper. Eliminates ~45 lines of duplicated index emission code across 4 dialects.
- **Fixed `unreachable` in `parse_index.zig`** — Replaced unreachable panic at line 92 with `return error.UnexpectedPrimaryKey` for safety (matching the existing guard at line 52).
- **Added Oracle dialect unit tests** (`dialect/oracle_test.zig`) — 10 tests covering type rendering (12 types), quoting, capabilities, PRIMARY KEY, timestamp modifier, CREATE VIEW, enum CHECK, and generated columns.
- **Added Db2 dialect unit tests** (`dialect/db2_test.zig`) — 11 tests covering type rendering (12 types), quoting, capabilities, PRIMARY KEY with/without IDENTITY, timestamp modifier, CREATE VIEW, enum CHECK, and generated columns.
- **Expanded pipeline tests** (`pipeline/forward_test.zig`) — 7 tests (up from 2) covering: simple schema, invalid input, FK columns, enum types, template inheritance, multiple tables, and default values.

### v0.71.0 (2026-08-02)

- **Shared generator test helpers** (`generators/common_test.zig`) — Extracted `makeTestTable`, `makeTestTableWithFks`, `makeTestTableWithIndexes`, `makeTestAst`, `makeTestAstWithName`, `makeTestColumn`, `makeTestColumnWithFlags` into a shared module. Eliminated ~120 lines of duplicated helper definitions across 8 generator test files (drizzle, knex, typeorm, sqlalchemy, prisma, docs, json_schema, sql_ddl, graphql, openapi).
- **Consolidated ORM default format callbacks** — Added `OrmTarget` enum and `getOrmFormatter()` factory to `generators/common.zig`. Pre-built formatters for drizzle, knex, sqlalchemy, and typeorm with shared `formatStringSingleQuoted`, `jsBoolTrue`/`jsBoolFalse`/`jsNull` callbacks. Eliminated ~60 lines of duplicated callback functions across 4 ORM generators.
- **Unified validate/check handlers** — `handleCheck` now delegates to `handleValidate` with `strict=true`, eliminating ~10 lines of duplicated error handling logic in `pipeline/forward.zig`.
- **Named constant for magic number** — Replaced magic number `32` with `MAX_CUSTOM_TYPE_DEPTH` in `types/type_resolver.zig` for circular custom type detection.

### v0.70.0 (2026-08-01)

- **IBM Db2 dialect** (`dialect/db2.zig`, ~250 lines) — complete Db2 LUW backend with double-quote identifier quoting, GENERATED ALWAYS AS IDENTITY for auto-increment, INTEGER/BIGINT/SMALLINT/DECIMAL(p,s)/VARCHAR(n)/CLOB/BLOB type mappings, BOOLEAN type (Db2 9.7+), CHECK constraints for enums, COMMENT ON for table/column comments, GENERATED ALWAYS AS (expr) STORED for generated columns (Db2 11.1+), and RENAME COLUMN support (Db2 10.5+).
- **Db2 dialect registration** — Added to `Dialect` enum, `getBackend()` switch, comptime validation, CLI `parseDialect` (accepts `db2` or `idb2`), and help text.
- **Db2 reverse mapping** — `DialectTypeMap` extended with `db2` field; 41+ REVERSE_MAP entries updated with Db2 type equivalents; reverse lookup includes Db2 types. Added Db2-specific passthrough types (DECFLOAT, GRAPHIC, VARGRAPHIC).
- **103 new golden tests** in `tests/test_db2.sh` covering all-types, modifiers, defaults, templates, FK, indexes, checks, enums, inline indexes, generated columns, views, and imports.
- **Drizzle ORM generator** — Db2 support via `pg-core` driver fallback.
- **Test coverage** — Added Oracle and Db2 test suites to `test_coverage.sh` (18 suites total).
- **Fixed unit tests** — Updated CLI test for new Db2 dialect, updated reverse map test to include Db2 field.
- Documentation: updated Source Layout, Dialect Enum, Quick Usage, and test counts.

### v0.69.0 (2026-08-01)

- **Extracted CHECK constraint parsers** — Moved `parseRange`, `parseComparison`, `parseInList`, `writeJsonValue`, and `findFkRefTable` from `json_schema.zig` and `openapi.zig` into shared `generators/common.zig`. Eliminates ~160 lines of verbatim duplicated code across two generators.
- **Extracted shell completions from main.zig** — Moved `COMPLETIONS_BASH/ZSH/FISH/POWERSHELL` constants, `STARTER_SCHEMA`, `handleInit`, and `handleCompletions` into a new `completions.zig` module. Reduces `main.zig` from ~500 to ~200 lines.
- **Refactored migrate.zig emitFieldDiffs** — Extracted each action branch (add/drop/modify/rename) into its own focused function (`emitAddField`, `emitDropField`, `emitModifyField`, `emitRenameField`). Improved readability of 56-line switch statement.
- **Unified reverse codegen column emission** — Merged duplicate template vs non-template column loops in `reverse/codegen.zig` into a single loop with inline template filtering.
- **Added FieldDiff re-export** — `diff/engine.zig` now re-exports `FieldDiff` from `diff/types.zig` for consistent access.
- **Fixed OpenAPI golden test versions** — Updated expected files from `0.59.0` to `0.69.0`.

### v0.68.0 (2026-08-01)

- **`rune fmt` command** — Auto-format `.ss` schema files with consistent style: 2-space indentation for fields inside tables/templates, trailing whitespace removal, single blank line between blocks, no trailing blank lines. 10 unit tests.
- **Unified docs generators** — Removed duplicate `src/docs.zig` (215 lines). The `docs` CLI command now routes through the generator registry (`generators/docs.zig`), same as `rune generate docs`. Eliminates code duplication and ensures consistent output.
- **Fixed GraphQL view placeholder** — Removed fake `_placeholder: String` field from GraphQL view types. Views now emit a comment explaining columns are derived from the SQL query.
- **Fixed migration rollback MODIFY COLUMN** — Rollback SQL generation now passes the codegen instance through, ensuring column definitions are emitted for dialects that require them (MySQL, MSSQL, Oracle). Previously produced incomplete rollback SQL.
- **Inlined type_registry.zig** — Removed thin delegation layer; `lookupSqlTypeDirect` is now called directly from `sql_type.zig`. Reduces indirection.
- Documentation: updated Source Layout, Quick Usage, shell completions, and test counts.

### v0.67.0 (2026-08-01)

- **Oracle SQL dialect** (`dialect/oracle.zig`, ~300 lines) — complete Oracle backend with double-quote identifier quoting, NUMBER precision/scale, VARCHAR2/CLOB/BLOB type mappings, CHECK constraints for enums, COMMENT ON for table/column comments, GENERATED ALWAYS AS for generated columns (12c+), and RENAME COLUMN support.
- **Oracle dialect registration** — Added to `Dialect` enum, `getBackend()` switch, comptime validation, CLI `parseDialect` (accepts `oracle` or `ora`), and help text.
- **Oracle reverse mapping** — `DialectTypeMap` extended with `oracle` field; 41 REVERSE_MAP entries updated with Oracle type equivalents.
- **103 new golden tests** in `tests/test_oracle.sh` covering all-types, modifiers, defaults, templates, FK, indexes, checks, enums, inline indexes, generated columns, views, and imports.
- **Drizzle ORM generator** — Oracle support via `pg-core` driver fallback.
- Documentation: updated Source Layout, Dialect Enum, CLI help, and test counts.

### v0.66.0 (2026-08-01)

- **`rune init` command** — scaffolds a new project with a starter `.ss` file containing users, posts, and comments tables with FK references, indexes, and enum types. Usage: `rune init [name] [-o output]`.
- **Shell completion scripts** — `rune completions bash|zsh|fish|powershell` generates completion scripts for each shell. Install: `source <(rune completions bash)`.
- **Fuzz testing infrastructure** — `tests/fuzz.sh` generates random `.ss` input and checks for parser crashes. Usage: `bash tests/fuzz.sh [iterations]`.
- 12 new golden tests in `tests/test_init.sh` covering init, completions, and dialect output.
- Documentation: updated Source Layout, Generator Registry, Module Roles, and test counts.

### v0.65.0 (2026-08-01)

- **GraphQL type definitions generator** (`rune generate graphql`) — generates GraphQL SDL type definitions from `.ss` files. Produces object types, input types, enum types, Query fields (single + list), and Mutation fields (create/update/delete). SQL type mapping: int→Int, varchar→String, boolean→Boolean, datetime→DateTime (custom scalar), decimal→Float, bigint→String, json→JSON (custom scalar). Enum columns generate standalone `enum` types. FK columns produce relation fields. Views generate read-only types with Query entries (no mutations).
- 9 new unit tests for GraphQL generator (`generators/graphql_test.zig`).
- 4 new golden tests (`test_graphql.sh`) covering basic types, FK references, enums, and views.
- Generator registry expanded from 10 to 11 generators.
- Documentation: updated Source Layout, Generator Registry, Module Roles, and test counts.

### v0.64.0 (2026-08-01)

- **TypeORM FK emission fix** — TypeORM generator now correctly emits `@ManyToOne` + `@JoinColumn` decorators for FK columns. Previously silently dropped all foreign key relations.
- **Knex varchar(0) fix** — Knex generator defaults to 255 when varchar length is 0, matching other generators.
- **SQLAlchemy multi-index fix** — Single `__table_args__` tuple for all table-level constraints instead of one per index.
- **Partial schema compilation** — Pipeline continues with semantic analysis and codegen when parse errors exist, producing SQL for valid tables only. Warning shows count of skipped tables.
- **MSSQL unit tests** — 9 new tests for `dialect/mssql.zig` covering type rendering, quoting, capabilities, and generated columns.
- Version bumped to 0.64.0.

### v0.63.0 (2026-08-01)

- **Synchronized multi-error recovery** — Parser now records all syntax errors in a single pass via `DiagnosticCollector` and returns a partial AST with `error_count` field. Users see all parse errors at once instead of stopping at the first one. Pipeline uses `tokenizeAndParseWithLines` which always returns the tree (even with errors), enabling future partial schema compilation.
- **`Ast.error_count` field** — New field on `types/ast.zig` Ast struct tracks the number of parse errors recorded during parsing. When > 0, the AST is partial (some tables/templates may be missing). Used by the pipeline to determine whether semantic analysis should proceed.
- **`tokenizeAndParseLenient` function** — New function in `pipeline/import_resolver.zig` that returns the parsed tree without printing errors. Used internally by the pipeline for scenarios where error printing should be deferred.
- **VERSION sync** — Fixed VERSION file (was 0.61.0, now 0.63.0 to match version.zig).
- Version bumped to 0.63.0.

### v0.62.0 (2026-08-01)

- **TypeInfo methods** — Added `isNumeric()`, `isString()`, `isDatetime()`, `isBoolean()` directly on `TypeInfo` in `types/ast.zig`. Collocates type classification behavior with the type definition. Updated `type_map.zig` and `pipeline/forward.zig` to delegate to the new methods (also fixes `isNumericSymType` missing `m`, `M`, `p` symbols).
- **Table-driven CLI subcommand dispatch** — Replaced the 11-branch sequential if/else chain in `cli.zig` with a comptime `parsers` array of `{name, parse_fn}` entries. Adding a new subcommand now requires only one table entry plus a parser function.
- **Pipeline stats extraction** — Moved `computeStats()` and `classifyFieldType()` from `pipeline/forward.zig` into `pipeline/stats.zig`. Single-responsibility module for schema statistics.
- **Documentation sync** — Removed references to non-existent `detectConflicts()`/`getParallelGroups()` from CLAUDE.md. Added `TypeInfo Methods` and `Table-Driven Subcommand Dispatch` to Key Design Patterns. Added `stats.zig` to Module Roles.
- Version bumped to 0.62.0.

### v0.61.0 (2026-08-01)

- **View UNION/UNION ALL/INTERSECT/EXCEPT support** — Views now support set operations. The parser detects UNION keywords in view queries and splits them into structured AST fields (`union_op`, `second_query`). Codegen emits the combined query. Diff engine properly compares union views. Docs generator shows the full query including set operations.
- **PostgreSQL type expansion** — Added `xml`, `cidr`, `macaddr` as passthrough types in `REVERSE_MAP`. These PostgreSQL-specific types are now properly recognized during reverse engineering and emitted as-is in `.ss` output.
- **`rune stats` command** — New subcommand that prints detailed schema statistics including field type breakdown: non-null count, numeric, string, datetime, boolean, and other types.
- **Reverse engineering JSON output** (`rune reverse --format json`) — Reverse command now supports `--format json` to output structured JSON with table names, column definitions (name, type, primary_key, auto_increment, nullable, default), indexes, and foreign keys.
- Version bumped to 0.61.0.

### v0.60.0 (2026-08-01)

- **OpenAPI 3.1 generator** (`rune generate openapi`) — generates OpenAPI 3.1 specification from `.ss` files. Produces `components/schemas` with table object definitions, property type mappings (via JSON Schema), required arrays, FK `$ref` references, enum values, CHECK constraint metadata, and default values. Views included as read-only schemas.
- 8 new unit tests for OpenAPI generator (`generators/openapi_test.zig`).
- 3 new golden tests (`test_openapi.sh`) covering basic schemas, FK references, and template inheritance.
- Generator registry expanded from 8 to 9 generators.
- Documentation: added MSSQL column to `type.md` core types table, fixed unsigned prefix in `grammar.ebnf`, updated test counts across all docs.

### v0.59.0 (2026-07-31)

- **Fix critical test infrastructure bug** — All golden test scripts using `set -euo pipefail` crashed silently when `diff` returned non-zero (files differ). Root cause: `diff_output=$(diff ... | head -20)` fails with `pipefail`. Fixed by adding `compare_files()`, `diff_versions()` helpers to `lib.sh` using process substitution.
- **Version-resilient golden tests** — Removed `-- Generated by rune X.Y.Z` version comment from all 276 golden files. Test scripts now use `strip_version()` to strip version from actual output before comparison. Version bumps no longer break golden tests.
- **Add MSSQL to test coverage** — `tests/test_mssql.sh` (26 tests) added to `test_coverage.sh`. Previously existed but was not included in the full test suite runner.
- **Updated test counts** — PostgreSQL 83→87, SQLite 24→26, Reverse 15→21, Roundtrip 23→68 (all reflect actual test counts after test additions in prior versions)
- Test results: All 15 test suites pass (486 golden tests + unit tests)

### v0.58.0 (2026-07-31)

- **Stabilize benchmark infrastructure** — Increased default iterations from 10 to 50 for more stable results. Added 3-iteration warmup phase to stabilize CPU cache. Added `--diff` mode for per-stage comparison with baseline.
- **Add `rune validate --strict` mode** — `rune validate --strict` now exits with code 1 when the schema has errors, useful for CI/CD pipelines that need strict validation. Default behavior (exit 0) remains unchanged for backward compatibility.
- **Add roundtrip golden tests** — Added 14 new roundtrip tests (23 total, up from 9) covering all-types, modifiers, suffix-inference, table-comment, template-deep, template-override, empty-lines, slot-beginning, slot-end, unicode-comments, bare-fields, many-defaults, generated-columns, and custom-types.
- **Add PostgreSQL golden tests** — Added 2 new PostgreSQL tests (view-multi, warn-invalid-modifiers).
- **Add SQLite golden test** — Added 1 new SQLite test (sqlite-types) covering boolean and JSON types.
- Test results: All 14 test suites pass (688 total tests)

### v0.57.0 (2026-07-31)

- **Fix `handleValidate` silent failure** — `rune validate` now prints "schema has errors" when the schema has semantic errors, instead of silently returning with no output. Exit code remains 0 (validate is permissive by design).
- **Remove unused pass_manager parallelism code** — Removed `detectConflicts`, `hasConflict`, `dependsOn`, `transitiveDependsOn`, `getParallelGroups`, `canRunConcurrently`, and `ParallelGroup` from `semantic/pass_manager.zig`. These were never called from production code. Kept `validateDependencyOrder` which is used by the analyzer.
- **Consolidate duplicate generator helpers** — Drizzle generator now uses `common.tableHasNonPkIndexes` and `common.tableHasCompositeFks` instead of local duplicates. Removed 3 unused functions from `generators/common.zig` (`hasEnumColumns`, `findFkForColumn`, `writeEnumValuesJoin`).
- **Improve CLI error messages** — `main.zig` error dispatch now shows human-readable messages for common errors (`OutOfMemory`, `FileNotFound`, `AccessDenied`, `IsDir`, `NotDir`) instead of just the enum name.
- **Separate benchmark timing** — `bench.zig` now measures tokenize and parse stages independently instead of combining them. Both stages are timed separately in `runPipelineTimed`.
- **CLI `-o` flag validation** — `parseOutputFlag` now rejects values starting with `-` (indicating a missing output path).
- Test results: 588 pass, 14 fail, 3 crash (605 total); 525 leaks

### v0.56.0 (2026-07-30)

- **Microsoft SQL Server dialect** (`dialect/mssql.zig`, ~260 lines) — complete MSSQL backend with square bracket identifier quoting, IDENTITY support, NVARCHAR/NVARCHAR(MAX)/VARBINARY(MAX)/DATETIME2/BIT type mappings, CHECK constraints for enums, schema-qualified names, and batch separator support.
- **Dialect registration** — MSSQL added to `Dialect` enum, `getBackend()` switch, comptime validation, CLI `parseDialect` (accepts `mssql` or `sqlserver`), and help text.
- **Reverse mapping** — `DialectTypeMap` extended with `mssql` field; 41 REVERSE_MAP entries updated with MSSQL type equivalents; reverse lookup includes MSSQL types.
- **Drizzle ORM generator** — MSSQL support via `mssqlTable` / `mssql-core` imports.
- **Golden tests** — 26 MSSQL golden tests in `tests/test_mssql.sh` covering all-types, modifiers, defaults, templates, FK, indexes, checks, enums, unsigned, inline indexes, generated columns, and views.
- Test results: 597 pass, 14 fail, 3 crash (614 total); 525 leaks

### v0.55.0 (2026-07-30)

- **Compound FK parsing** — multi-dot references (`projects.org_id.project_id`) now correctly split into table + individual fields. Multiple local fields before a dotted reference are supported.
- **FK test memory leaks fixed** — `parse_fk_test.zig` now properly frees all inner string allocations via `freeFk` helper. All 9 FK tests pass with zero leaks.
- **`parseDottedRef` helper** — extracted reusable function for splitting dotted references with trailing-dot fallback.
- **DiagnosticCollector overflow tests** — new tests verify `max_errors` limit stops error recording and warnings don't count toward the limit.
- Test results: 598 pass, 13 fail, 3 crash (614 total); 525 leaks (was 593/14/3/610/532)

### v0.54.0 (2026-07-30)

- **Tokenizer test fixes** — corrected 18 unit test expectations in `tokenizer_test.zig` to match actual compiler behavior. Fused type modifiers (`n++`) are kept as single tokens (parser's `parseFusedTypeModifier` handles them). Fixed4 test expectations: fused type modifier (2 tokens, not3), enum type (5 tokens, not7), comment stops at -- (2 tokens, not3), inline FK (4 tokens, not5).
- **Memory leak fix** — added proper token array cleanup in `tokenizeAll: mixed content` test, reducing leak count from535 to532.
- **Test file count** — updated CLAUDE.md to reflect58 colocated test files (was51).

### v0.53.0 (2026-07-30)

- **Shared default value formatting** — extracted `writeDefault` from 4 ORM generators (drizzle, knex, typeorm, sqlalchemy) into `generators/common.zig` with `DefaultFormatter` callback struct. ~120 lines of duplicated parsing logic consolidated into a single shared function.
- **Parser safety** — replaced unsafe `@intFromPtr` pointer arithmetic in `parse_field.zig` with safe `std.mem.indexOf` for generated column expression extraction.
- **New test coverage** — 22 unit tests for `parse_recovery.zig` (16) and `import_resolver.zig` (6), covering error recording, block boundary detection, line splitting, and base directory computation.

### v0.52.0 (2026-07-30)

- **Migration engine refactoring** — unified forward/rollback codepaths, eliminating ~180 lines of duplicated emit functions via shared `Direction` enum.
- **Consolidated whitespace helpers** — merged duplicate `skipWhitespaceAndComments` / `skipWhitespaceAndCommentsNoSemicolon` into single function.
- **Safety fixes** — replaced 3 unsafe `unreachable` statements in runtime code with proper error handling (`parse_index.zig`, `reverse/codegen.zig`).

### v0.51.0 (2026-07-30)

- **TypeORM generator** (`rune generate typeorm`) — generates TypeORM entity classes from `.ss` files. Supports `@Entity`, `@Column`, `@PrimaryGeneratedColumn`, `@ManyToOne`, `@JoinColumn`, `@Index` decorators. TypeScript type inference for all SS types.
- **SQLAlchemy generator** (`rune generate sqlalchemy`) — generates SQLAlchemy ORM models from `.ss` files. Supports `Column()`, `ForeignKey`, `Index`, `UniqueConstraint`, `declarative_base`. Python type mapping for all SS types.
- **Knex.js generator** (`rune generate knex`) — generates Knex.js migration files from `.ss` files. Supports `createTable`, `table.increments`, `table.foreign().references()`, `table.index()`, `exports.up`/`exports.down` pattern.
- 24 new unit tests (8 per generator).
- `rune generate --list` now shows8 generators.
- All generators registered in `REGISTRY` — no `main.zig` changes needed.

### v0.50.0 (2026-07-30)

- **DialectTypeMap refactoring** — `reverse_map.zig` now uses a `DialectTypeMap` struct instead of per-dialect named fields. Adding a new dialect no longer requires editing 88+ struct entries.
- **Generator module relocation** — `json_schema.zig` moved from `src/` root to `generators/json_schema.zig` for consistent structure.
- **Shared generator helpers** — new `generators/common.zig` with `hasEnumColumns()`, `findFkForColumn()`, `writeEnumValuesJoin()`, `tableHasNonPkIndexes()`, `tableHasCompositeFks()`.
- Updated all callers: `reverse/map.zig`, `dialect/sqlite.zig`, `types/type_map_test.zig`, `reverse/map_test.zig`, `pipeline/forward.zig`.
- 292 golden tests pass (MySQL 86, PG 85, SQLite 25, Reverse 21, Diff 12, Migration 34, Roundtrip 26, JSON Schema 3).

### v0.49.0 (2026-07-30)

- Drizzle ORM generator — TypeScript schema with pgTable/mysqlTable/sqliteTable, column modifiers, FK references, indexes, enum types
- Enhanced JSON Schema generator — `$defs`, `$ref` for tables and FK references, proper `required` arrays, `additionalProperties: false`
- 14 new generator unit tests
- `rune generate --list` now shows 5 generators

### v0.48.0 (2026-07-29)

- 3 new generators: SQL DDL, Prisma, Markdown docs
- main.zig error dispatch refactor — extracted `cliArgErrorMessage` helper
- 16 new unit tests
- Updated 244 golden test files

### v0.47.0 (2026-07-29)

- Module splits — `pipeline/import_resolver.zig`, `diff/migrate_helpers.zig`
- Auto-computed parallel groups in `pass_manager.zig`
- Added `grammar.ebnf`, `schema.md`, `type.md` documentation

### v0.46.0 (2026-07-29)

- CLI parseArgs refactor — subcommand-specific functions with GlobalFlags struct
- Safe optional unwraps — 3 unsafe `result.resolved.?` panics → explicit errors
- validate_indexes decomposition

### v0.45.0 (2026-07-29)

- DialectCapability system — 12 feature flags per dialect backend
- CompileConfig struct — replaced 13-parameter `handleCompileRequest`
- Generator API dialect awareness
- CLI unknown-flag detection
- Allocator consistency fixes
- 5 new io.zig unit tests; updated 247 golden files

### v0.43.0 (2026-07-29)

- Generator registry — pluggable `Generator` struct with `REGISTRY` array
- Memory leak fixes in `detectConflicts()` and `transitiveDependsOn()`
- Parallel golden test runner (`test_parallel.sh`)

### v0.42.0 (2026-07-29)

- Buffer overflow fix in `reverse/map.zig`
- Extracted `hasChanges()` on `SchemaDiff`
- Added `rune generate` subcommand with JSON Schema generator
- 8 new unit tests

### v0.41.0 (2026-07-29)

- DiagnosticCollector error count caching
- Replaced `std.debug.panic` with proper error return
- Doc comments on public APIs
- 28 new unit tests (docs + migrate_json); total 526

### v0.40.0 (2026-07-29)

- Memory leaks reduced 606 → 533 (73 fewer)
- Fixed `validate` vs `check` CLI behavior
- Redundant allocation fixes across 8 files

### v0.39.0 (2026-07-29)

- Unused template warning
- "Did you mean?" suggestions (Levenshtein edit distance)
- Fixed `catch unreachable` in pass_manager and validate_template_types
- 15 new unit tests (484 → 499)

### v0.38.0 (2026-07-28)

- Fixed ast_visitor_test callbacks + memory leaks
- FK rename buffer overflow fix
- PG ALTER TABLE index emission fix

### v0.37.0 (2026-07-28)

- Fixed colocated test compilation (72 errors)
- `--json-errors` flag
- `rune check` subcommand

### v0.36.0 (2026-07-28)

- Comptime RenderEntry validation
- TypedAst `ss_symbol` cleanup
- Diff FK rename detection
- Shared test helpers extraction

### v0.35.0 (2026-07-28)

- Re-enabled colocated test files
- Fixed 9 compilation errors across test files
- `tests.zig` module index

### v0.34.0 (2026-07-27)

- Diff format module split (text/json/sarif)
- SARIF version from source

### v0.33.0 (2026-07-27)

- Extracted shared reverse mapping data
- Colocated test files
- 25 new reverse map tests

### v0.32.0 (2026-07-27)

- renderType table-driven refactor
- PassContext read/write runtime validation
- CLI command registry
- vtable null safety

### v0.31.0 (2026-07-27)

- PassAccess runtime enforcement
- DialectBackend optional method comptime checks
- Reverse engineering confidence system
- SARIF output
- `rune docs` command
- Import search paths

### v0.30.0 (2026-07-27)

- DialectBackend vtable reorganization
- Import parse cache
- PassAccess declarations
- Stdin pipeline tests

### v0.11.0 – v0.29.0

- Schema import/include
- Migration rollback
- Virtual/generated columns
- JSON Schema output
- Diff/migrate CLI flags
- Validate subcommand
- Benchmark infrastructure

### v0.1.0 – v0.10.0

- Core forward pipeline (`.ss` → SQL)
- Four dialect backends (MySQL, PostgreSQL, SQLite, MSSQL)
- Reverse engineering
- Diff engine
- Migration generation
- Template system
- CHECK constraints, indexes, foreign keys
- Custom types
