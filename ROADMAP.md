# Rune Roadmap

This document outlines the planned evolution of Rune toward becoming a **universal database schema interchange format**. A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.89.0 (2026-08-03) — 29,500+ lines production Zig, 870+ tests, 21 test suites.

---

## Legend

- [x] Done — shipped in a release
- [ ] Planned — not yet started
- [~] In progress — partial implementation exists
- Priority is top-down within each phase; phases overlap in practice
- Version numbers are approximate — shipped when ready, not by deadline

---

## Phase 1: Core Solidification ✅

Polish the existing foundation. **Complete** — all items shipped in v0.38–v0.81.

### Parser & Error Recovery

- [x] Synchronized multi-error recovery — report all syntax errors in one pass instead of fail-fast (v0.63.0)
- [x] Partial schema compilation — emit valid SQL for correct tables even when others have errors (v0.64.0)

### Semantic Analysis

- [x] Cycle detection for template inheritance
- [x] FK target validation — error when inline FK references a non-existent table or column
- [x] Unused template warning (v0.39.0)
- [x] Duplicate column name detection within a table
- [x] "Did you mean?" suggestions — Levenshtein edit distance for misspelled references (v0.39.0)

### Testing

- [x] Fuzz testing infrastructure — random `.ss` input to find parser crashes (v0.66.0)
- [x] Golden test parallelization — `tests/test_parallel.sh` runs suites concurrently (v0.43.0)
- [x] Property-based tests for roundtrip fidelity (`.ss` → compile → reverse → compile → compare) (v0.85.0)

---

## Phase 2: Extended Dialect Support ✅

Add enterprise SQL dialects. **Complete** — all 6 dialects shipped in v0.48–v0.76.

### New Dialect Backends

- [x] **PostgreSQL** — `dialect/pg.zig`. `SERIAL`/`BIGSERIAL`, `TEXT`, `BOOLEAN`, `JSONB`, `INET`, `UUID`, schema-qualified names, `CREATE OR REPLACE VIEW`
- [x] **SQLite** — `dialect/sqlite.zig`. Type affinity hints, `AUTOINCREMENT`, `BOOLEAN` as `INTEGER`, `JSON` as `TEXT`
- [x] **Microsoft SQL Server** — `dialect/mssql.zig` (~260 lines). `IDENTITY`, `NVARCHAR`/`NTEXT`, schema-qualified names (`dbo.table`), `GO` batch separators (v0.56.0)
- [x] **Oracle** — `dialect/oracle.zig` (~300 lines). No `AUTO_INCREMENT` (sequences + triggers), `NUMBER` precision/scale, `VARCHAR2`/`NVARCHAR2`, double-quote identifier quoting (v0.67.0)
- [x] **IBM Db2** — `dialect/db2.zig` (~250 lines). `GENERATED ALWAYS AS IDENTITY`, `BIGINT`/`INTEGER`/`SMALLINT`, `DECIMAL(p,s)`, `COMMENT ON`, `GENERATED ALWAYS AS (expr) STORED` (v0.70.0)

### Dialect Infrastructure

- [x] Dialect capability flags — 12 feature flags per backend (v0.45.0)
- [x] Generator API dialect awareness (v0.45.0)
- [x] CLI unknown-flag detection (v0.45.0)
- [x] `DialectBackend` vtable — 33 function pointers (26 required + 7 optional)
- [x] Shared dialect helpers — `dialect/common.zig` (~350 lines) consolidating duplicated logic

### Dialect Testing & Reverse

- [x] Dialect-specific test suites — `test_oracle.sh` (103), `test_mssql.sh` (26), `test_db2.sh` (103), `test_postgres.sh` (87), `test_sqlite.sh` (26)
- [x] `rune reverse --dialect <d>` — dialect-aware reverse engineering per backend (v0.73.0–v0.76.0)
- [x] Dialect auto-detection — `reverse/dialect_detect.zig` detects all 6 dialects from DDL patterns (v0.74.0)
- [x] Shared reverse mapping data — `types/reverse_map.zig` with 52+ entries covering all 6 dialects

---

## Phase 3: ORM & API Schema Output ✅

Bridge the gap between database schema and application code. **Complete** — all generators shipped in v0.48–v0.65.

### ORM Generators

- [x] `rune generate prisma schema.ss` (v0.48.0)
- [x] `rune generate drizzle schema.ss` — TypeScript with pgTable/mysqlTable/sqliteTable/mssqlTable (v0.49.0)
- [x] `rune generate typeorm schema.ss` — TypeORM entity classes with decorators (v0.51.0)
- [x] `rune generate sqlalchemy schema.ss` — SQLAlchemy ORM models with Column/ForeignKey/Index (v0.51.0)
- [x] `rune generate knex schema.ss` — Knex migration files with up/down (v0.51.0)

### API Schema

- [x] `rune generate openapi schema.ss` — OpenAPI 3.1 spec with `$defs`/`$ref` (v0.60.0)
- [x] `rune generate graphql schema.ss` — GraphQL SDL type definitions with Query/Mutation (v0.65.0)
- [x] `rune generate json-schema schema.ss` — `$defs`, `$ref`, proper `required` arrays (v0.49.0)
- [x] `rune generate symbol-index schema.ss` — JSON symbol index for IDE integration (v0.88.0)

### Generator Infrastructure

- [x] `rune generate --list` — show available generators (v0.48.0)
- [x] Generator registry — pluggable `Generator` struct with `REGISTRY` array (v0.43.0)
- [x] SQL DDL generator (v0.48.0)
- [x] Markdown docs generator (v0.48.0)
- [x] Shared generator test helpers — `generators/common_test.zig` (v0.71.0)
- [x] Shared ORM default formatter — `generators/common.zig` with `OrmTarget` (v0.71.0)
- [ ] Generator plugin system — user-defined generators via Zig plugins or WASM modules
- [ ] Template overrides — `.rune-template` files for customizing generator output

---

## Phase 4: Incremental & Live Workflows

Move from batch compilation to interactive, incremental usage. **Not started.**

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

Make Rune delightful to use day-to-day. **Partially started** — `rune init`, completions, and `rune fmt` shipped.

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
- [x] Shell completion scripts — `rune completions bash|zsh|fish|powershell` (v0.66.0)
- [x] `rune fmt` — auto-format `.ss` files (v0.68.0)
- [ ] `rune playground` — web-based `.ss` editor with live compilation (WASM)
- [ ] Colored output — syntax-highlighted SQL and diff output

---

## Phase 6: Ecosystem & Community

Build the community and ecosystem around Rune. **Not started.**

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
- [x] Benchmark CI gate — enforce no regressions beyond 10% (v0.82.0)
- [x] Benchmark dialect parameterization — `rune bench --dialect <d>` supports all 6 dialects (v0.74.0)
- [x] Benchmark stage breakdown — tokenize and parse measured independently (v0.57.0)

### Code Quality

- [x] Remove all `catch unreachable` in production code (v0.39.0)
- [x] Remove all unsafe `@intCast`/`@enumFromInt` in production code (v0.80.0)
- [x] Named constants for magic numbers — `STDIN_BUFFER_SIZE`, `OUTPUT_BUFFER_SIZE`, etc. (v0.80.0)
- [x] Eliminate `std.process.exit` in library code — all errors propagate to main.zig (v0.80.0)
- [ ] Zero-allocation codegen path — reuse buffers across compilations
- [ ] Formalize IR versioning — schema for forward/backward compatibility
- [ ] Memory leak audit — reduce remaining leaks toward zero
- [ ] Fuzz testing expansion — longer runs, more seed variety, coverage-guided mutation

### Platform

- [ ] Cross-compile to WASM — enable browser and Deno usage
- [ ] Windows native builds — test and document MSVC/MinGW paths
- [ ] ARM64 CI — test on Apple Silicon and ARM Linux

---

## Release History

### v0.89.0 (2026-08-03)

- **Replaced io_test.zig tautological tests** — Removed 5 meaningless tests that verified `std.mem.eql(u8, "-", "-")` and `null == null`. Replaced with 17 meaningful tests covering `optionalStrEq` and `jsonEscapeString` from `utils.zig`.
- **Expanded SqlType test coverage** — `types/sql_type_test.zig` expanded from 1 to 22 tests. Covers `toSql()` for MySQL/PG/SQLite across int, bigint, text, varchar, boolean, datetime, json, uuid types. Covers `toJsonSchema()` for integer, string, boolean, object, date-time, uuid, decimal, blob types.
- **Expanded ReverseConfig test coverage** — `pipeline/reverse_test.zig` expanded from 1 to 3 tests. Covers default values, custom values, and partial override scenarios.

### v0.87.0 (2026-08-02)

- **Shared dialect type rendering helpers** — Extracted `common.emitVarchar`, `common.emitDecimal`, `common.emitEnumValues`, `common.emitEnumFixedType` to replace 18+ per-dialect render functions. Each dialect now specifies only its type names in a switch statement, falling through to a comptime render table for simple types.
- **Shared `emitAlterTableCommentShared`** — PG, Oracle, Db2 now use a single shared `COMMENT ON TABLE` implementation instead of 3 identical copies.
- **Shared `emitIndexWithQuote`** — MSSQL, Oracle, Db2 now use a single shared index rendering function with configurable fulltext prefix (`"FULLTEXT "` for MSSQL, `""` for Oracle/Db2).
- **Consolidated `emitAlterEngine`** — Oracle, MSSQL, Db2 now reference `common.emitAlterEngineWarning` directly instead of 3 identical local implementations.
- **Removed dead `canonicalSimple` dialect parameter** — The unused `dialect` parameter in `diff/semantic.zig:canonicalSimple`, `simpleEquiv`, and `typeInfoEquiv` has been removed. All callers updated.

### v0.86.0 (2026-08-02)

- **Extensible DialectTypeMap** — Refactored `types/reverse_map.zig` to use `DIALECT_NAMES` comptime array and `getDialectType()` accessor. Adding a new dialect now requires updating only 3 locations (enum, struct field, switch case) instead of modifying every REVERSE_MAP entry. `reverse/map.zig` now uses comptime iteration over all dialects instead of a hardcoded `or` chain.
- **Bench stage count comptime** — Added `STAGE_NAMES` comptime constant to `bench.zig`. `stagePairs` now uses `STAGE_NAMES.len` instead of hardcoded `[5]`. Adding a new benchmark stage is documented as a 4-step process.
- **Fixed bench baseline format mismatch** — `test_bench.sh` now auto-migrates legacy `baseline.json` to per-dialect format. Detects and uses `bench.zig` binary when available for per-stage timing.
- **Improved `std:` import diagnostics** — `import_resolver.zig` now emits a warning when an `std:` import path cannot be resolved in any search path, instead of silently falling back to the literal path.
- **Completions unit tests** — New `completions_test.zig` with 16 tests covering all 4 shell completion scripts (bash, zsh, fish, powershell) and the starter schema template.

### v0.85.0 (2026-08-02)

- **Property-based roundtrip tests** — New `tests/test_property_roundtrip.sh` generates random `.ss` schemas, compiles → reverses → recompiles, verifies structural and semantic properties. Completes Phase 1 of ROADMAP.
- **Markdown diff format** — `rune diff --format markdown` produces clean markdown tables for PR descriptions and documentation. New `diff/format/markdown.zig` with 3 unit tests.
- **Cross-dialect roundtrip expansion** — Roundtrip tests expanded from 3 to 5 dialects (added Oracle, Db2). Total: 112 roundtrip tests (was 68).
- **Fixed OpenAPI golden test infrastructure** — Test script and golden files corrected (`.sql` → `.json`). 3/3 passing.
- **Fixed GraphQL golden test infrastructure** — Test script and golden files corrected (`.sql` → `.graphql`). 4/4 passing.
- **Fixed JSON Schema golden files** — Regenerated to match current generator output. 3/3 passing.

### v0.84.0 (2026-08-02)

- **Fixed thread-safety in GraphQL generator** — Replaced static `_enum_buf` buffer in `generators/graphql.zig` with allocator-allocated string. Eliminates potential race condition. Tests updated to use arena allocators (matching real CLI behavior).
- **Removed dead `Direction` enum** — Removed unused `Direction` enum from `diff/migrate.zig`.
- **Extracted shared `toCamelSingular`** — Moved `toCamelSingular` from `generators/prisma.zig` and `generators/graphql.zig` into `generators/common.zig`. Eliminates duplicated code.
- **Added `TypeInfo` unit tests** — New `types/ast_test.zig` with 22 tests covering `TypeInfo.eql`, `isNumeric`, `isString`, `isDatetime`, `isBoolean` methods.
- **Improved OOM error handling in `DiagnosticCollector`** — Added `oom` flag and `hadOom()` accessor. Replaces silent `std.debug.print` with trackable error state.
- **Cached `getBackend` in migration pipeline** — `diff/migrate.zig` now caches `getBackend(dialect)` in `generateFromDiff` and `generateRollback` to avoid redundant vtable lookups.

### v0.82.0 (2026-08-02)

- **Benchmark regression threshold tightened** — Reduced from 20% to 10%. Aligns with ROADMAP target. `bench.zig` now fails CI on >10% per-stage regression.
- **Benchmark prints all stages** — `printRegressionDetails` now shows all 5 stages with timing and change percentage (not just regressions). Improves developer visibility during benchmark runs.
- **Removed `last_unknown_flag` global state** — Replaced `pub var last_unknown_flag` in `cli.zig` with `findUnknownFlag()` function. Eliminates module-level mutable state for cleaner architecture.
- **New unit tests** — `cli_test.zig` expanded from 27 to 49 tests (all subcommands, all flags, error cases, `findUnknownFlag`). `bench_test.zig` expanded from 15 to 23 tests (StageTimes add/avg/total, regression threshold boundary tests).

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
- **Documentation sync** — Fixed stale module path references in ARCHITECTURE.md (`dialect_common.zig` → `dialect/common.zig`, `reverse_codegen.zig` → `reverse/codegen.zig`). Corrected vtable description from "23 core + 6 optional" to "26 required + 7 optional = 33 total function pointers". Fixed stale `type_map.zig` re-export claim in `sql_type.zig` and ARCHITECTURE.md.

### v0.78.0 (2026-08-02)

- **Consolidated dialect backend duplication** — Extracted 5 shared helpers into `dialect/common.zig`: `renderTypeFromTable`, `emitTableCommentStandalone`, `emitColumnCommentStandalone`, `emitCreateViewShared`, plus Oracle and Db2 now use existing `common.emitEnumTypeCheck`. Net reduction: ~80 lines of duplicated dialect code.
- **New unit tests** — Added `diff/engine_test.zig` with 7 tests covering the core diff engine.

### v0.77.0 (2026-08-02)

- **Fixed duplicate detection patterns** — Removed duplicate `GENERATED ALWAYS AS (` and `DECFLOAT` checks in `reverse/dialect_detect.zig`.
- **Fixed test_bench.sh cross-platform path** — Removed hardcoded Windows `.exe` suffix; now uses `lib.sh`'s `BIN_SUFFIX` variable.
- **Expanded test coverage runner** — Added OpenAPI and GraphQL test suites to `test_coverage.sh`.
- **ROADMAP accuracy** — Marked `rune init` (v0.66.0), `rune completions` (v0.66.0), and `rune fmt` (v0.68.0) as done.

### v0.76.0 (2026-08-02)

- **Expanded Oracle reverse engineering tests** — 7 tests (was 3): multi-word types, GENERATED BY DEFAULT AS IDENTITY, identity options, inline block comments, composite FKs.
- **Expanded Db2 reverse engineering tests** — 7 tests (was 3): GENERATED ALWAYS AS IDENTITY, BOOLEAN, BIGINT/SMALLINT, DOUBLE PRECISION, DECIMAL.
- **Parser unit tests** — 5 new tests for multi-word types, Oracle identity options, and Db2 types.
- **bench.zig refactoring** — Extracted `BenchArgs` config struct, `parseBenchArgs` helper, `stagePairs` shared iteration, and `Baseline.total()` method.

### v0.75.2 (2026-08-02)

- **Oracle dialect fixes** — Updated 103 golden files for corrected Oracle dialect output.

### v0.75.1 (2026-08-02)

- **SQL Parser enhancements** — Inline block comment parsing, Oracle identity options, multi-word type handling (TIMESTAMP WITH TIME ZONE, DOUBLE PRECISION, CHARACTER VARYING).
- **Reverse map expansion** — 52 new entries for Oracle and Db2 multi-word types.
- **Large schema test file** — 519-line comprehensive test schema with Chinese comments and complex templates.

### v0.75.0 (2026-08-02)

- **Pipeline config structs** — Added `DiffConfig`, `MigrateConfig`, and `ReverseConfig` structs to replace 8-11 positional parameters in pipeline handlers, following the existing `CompileConfig` pattern.
- **Unified diff/migrate handlers** — Merged 3 diff format handlers and 2 migrate format handlers into single functions that switch on `cfg.format`.
- **`generateFromSchema` helper** — Extracted compile→generate→write pattern from `main.zig` into `pipeline/forward.zig`.

### v0.74.0 (2026-08-02)

- **Benchmark dialect parameterization** — `rune bench --dialect <d>` benchmarks any SQL dialect.
- **Dialect auto-detection for all 6 dialects** — `reverse/dialect_detect.zig` now detects MSSQL, Oracle, and Db2 DDL patterns.
- 12 new benchmark unit tests, 7 new dialect detection tests.

### v0.73.0 (2026-08-02)

- **Dialect-aware reverse engineering for Oracle and Db2** — `reverseLookup` matches Oracle and Db2 type columns in `REVERSE_MAP`. Case-insensitive parameterized type matching (`VARCHAR2(N)`, `NUMBER(P,S)`, `DECIMAL(P,S)`).
- **Consolidated `emitAlterDropFk`** — Extracted FK name-joining logic from PG, MSSQL, Oracle into shared helpers.
- **Consolidated `emitAlterAddIndex`** — Extracted standalone CREATE INDEX logic from PG, Oracle, Db2, MSSQL into shared helper.
- **Added Oracle dialect unit tests** (10 tests) and **Db2 dialect unit tests** (11 tests).
- **Expanded pipeline tests** (`pipeline/forward.zig`) — 7 tests (up from 2).

### v0.71.0 (2026-08-02)

- **Shared generator test helpers** (`generators/common_test.zig`) — Eliminated ~120 lines of duplicated helper definitions across 10 generator test files.
- **Consolidated ORM default format callbacks** — Added `OrmTarget` enum and `getOrmFormatter()` factory. Eliminated ~60 lines of duplicated callback functions across 4 ORM generators.
- **Unified validate/check handlers** — `handleCheck` now delegates to `handleValidate` with `strict=true`.

### v0.70.0 (2026-08-01)

- **IBM Db2 dialect** (`dialect/db2.zig`, ~250 lines) — complete Db2 LUW backend.
- **Db2 reverse mapping** — 41+ REVERSE_MAP entries updated with Db2 type equivalents.
- **103 new golden tests** in `tests/test_db2.sh`.
- **Drizzle ORM generator** — Db2 support via `pg-core` driver fallback.

### v0.69.0 (2026-08-01)

- **Extracted CHECK constraint parsers** — Moved shared parsing logic into `generators/common.zig`. Eliminates ~160 lines of duplicated code.
- **Extracted shell completions from main.zig** — Moved into `completions.zig`. Reduces `main.zig` from ~500 to ~200 lines.
- **Refactored migrate.zig emitFieldDiffs** — Extracted each action branch into its own focused function.

### v0.68.0 (2026-08-01)

- **`rune fmt` command** — Auto-format `.ss` schema files with consistent style. 10 unit tests.
- **Unified docs generators** — Removed duplicate `src/docs.zig`. The `docs` CLI command now routes through the generator registry.
- **Fixed GraphQL view placeholder** — Views now emit a comment explaining columns are derived from the SQL query.
- **Fixed migration rollback MODIFY COLUMN** — Rollback SQL generation now passes the codegen instance through.

### v0.67.0 (2026-08-01)

- **Oracle SQL dialect** (`dialect/oracle.zig`, ~300 lines) — complete Oracle backend.
- **Oracle reverse mapping** — 41 REVERSE_MAP entries updated with Oracle type equivalents.
- **103 new golden tests** in `tests/test_oracle.sh`.

### v0.66.0 (2026-08-01)

- **`rune init` command** — scaffolds a new project with a starter `.ss` file.
- **Shell completion scripts** — `rune completions bash|zsh|fish|powershell`.
- **Fuzz testing infrastructure** — `tests/fuzz.sh` generates random `.ss` input.

### v0.65.0 (2026-08-01)

- **GraphQL type definitions generator** — produces GraphQL SDL type definitions with Query/Mutation fields.

### v0.64.0 (2026-08-01)

- **TypeORM FK emission fix** — TypeORM generator now correctly emits `@ManyToOne` + `@JoinColumn` decorators.
- **Partial schema compilation** — Pipeline continues with semantic analysis and codegen when parse errors exist.

### v0.63.0 (2026-08-01)

- **Synchronized multi-error recovery** — Parser records all syntax errors in a single pass via `DiagnosticCollector`.

### v0.62.0 (2026-08-01)

- **TypeInfo methods** — `isNumeric()`, `isString()`, `isDatetime()`, `isBoolean()` directly on `TypeInfo`.
- **Table-driven CLI subcommand dispatch** — Replaced sequential if/else chain with comptime `parsers` array.
- **Pipeline stats extraction** — Moved `computeStats()` into `pipeline/stats.zig`.

### v0.61.0 (2026-08-01)

- **View UNION/UNION ALL/INTERSECT/EXCEPT support**
- **`rune stats` command** — detailed schema statistics with field type breakdown.
- **Reverse engineering JSON output** (`rune reverse --format json`)

### v0.60.0 (2026-08-01)

- **OpenAPI 3.1 generator** — produces OpenAPI 3.1 specification with `$defs`/`$ref`.

### v0.59.0 (2026-07-31)

- **Fix critical test infrastructure bug** — All golden test scripts using `set -euo pipefail` crashed silently when `diff` returned non-zero.
- **Version-resilient golden tests** — Removed version comments from golden files; tests now strip version before comparison.

### v0.58.0 (2026-07-31)

- **Stabilize benchmark infrastructure** — 50 iterations, 3-iteration warmup, `--diff` mode.
- **Add `rune validate --strict` mode** — exits with code 1 when schema has errors.

### v0.57.0 (2026-07-31)

- **Fix `handleValidate` silent failure** — prints "schema has errors" when schema has semantic errors.
- **Remove unused pass_manager parallelism code** — removed `detectConflicts`, `getParallelGroups`, etc.
- **Separate benchmark timing** — tokenize and parse stages measured independently.

### v0.56.0 (2026-07-30)

- **Microsoft SQL Server dialect** (`dialect/mssql.zig`, ~260 lines) — complete MSSQL backend.

### v0.55.0 (2026-07-30)

- **Compound FK parsing** — multi-dot references (`projects.org_id.project_id`) correctly split.

### v0.54.0 (2026-07-30)

- **Tokenizer test fixes** — corrected 18 unit test expectations to match actual compiler behavior.

### v0.53.0 (2026-07-30)

- **Shared default value formatting** — extracted `writeDefault` from 4 ORM generators into `generators/common.zig`.
- **Parser safety** — replaced unsafe `@intFromPtr` with safe `std.mem.indexOf`.

### v0.52.0 (2026-07-30)

- **Migration engine refactoring** — unified forward/rollback codepaths, eliminating ~180 lines.
- **Safety fixes** — replaced 3 unsafe `unreachable` statements with proper error handling.

### v0.51.0 (2026-07-30)

- **TypeORM generator** — TypeORM entity classes with decorators.
- **SQLAlchemy generator** — SQLAlchemy ORM models with Column/ForeignKey/Index.
- **Knex.js generator** — Knex migration files with up/down.

### v0.50.0 (2026-07-30)

- **DialectTypeMap refactoring** — `reverse_map.zig` uses struct instead of per-dialect named fields.
- **Generator module relocation** — moved to `generators/` for consistent structure.
- **Shared generator helpers** — `generators/common.zig`.

### v0.49.0 (2026-07-30)

- **Drizzle ORM generator** — TypeScript schema with pgTable/mysqlTable/sqliteTable.
- **Enhanced JSON Schema generator** — `$defs`, `$ref`, proper `required` arrays.

### v0.48.0 (2026-07-29)

- 3 new generators: SQL DDL, Prisma, Markdown docs.
- main.zig error dispatch refactor.

### v0.47.0 (2026-07-29)

- Module splits — `pipeline/import_resolver.zig`, `diff/migrate_helpers.zig`.
- Documentation: `grammar.ebnf`, `schema.md`, `type.md`.

### v0.46.0 (2026-07-29)

- CLI parseArgs refactor — subcommand-specific functions with GlobalFlags struct.
- Safe optional unwraps — 3 unsafe `result.resolved.?` panics → explicit errors.

### v0.45.0 (2026-07-29)

- DialectCapability system — 12 feature flags per dialect backend.
- CompileConfig struct — replaced 13-parameter `handleCompileRequest`.
- Generator API dialect awareness.
- CLI unknown-flag detection.

### v0.43.0 (2026-07-29)

- Generator registry — pluggable `Generator` struct with `REGISTRY` array.
- Memory leak fixes.
- Parallel golden test runner.

### v0.42.0 (2026-07-29)

- Buffer overflow fix in `reverse/map.zig`.
- Added `rune generate` subcommand with JSON Schema generator.

### v0.41.0 (2026-07-29)

- DiagnosticCollector error count caching.
- Replaced `std.debug.panic` with proper error return.

### v0.40.0 (2026-07-29)

- Memory leaks reduced 606 → 533 (73 fewer).
- Fixed `validate` vs `check` CLI behavior.

### v0.39.0 (2026-07-29)

- Unused template warning.
- "Did you mean?" suggestions (Levenshtein edit distance).
- Fixed `catch unreachable` in pass_manager and validate_template_types.

### v0.38.0 (2026-07-28)

- Fixed ast_visitor_test callbacks + memory leaks.
- FK rename buffer overflow fix.
- PG ALTER TABLE index emission fix.

### v0.37.0 (2026-07-28)

- Fixed colocated test compilation (72 errors).
- `--json-errors` flag.
- `rune check` subcommand.

### v0.36.0 (2026-07-28)

- Comptime RenderEntry validation.
- TypedAst `ss_symbol` cleanup.
- Diff FK rename detection.

### v0.35.0 (2026-07-28)

- Re-enabled colocated test files.
- Fixed 9 compilation errors across test files.
- `tests.zig` module index.

### v0.34.0 (2026-07-27)

- Diff format module split (text/json/sarif).
- SARIF version from source.

### v0.33.0 (2026-07-27)

- Extracted shared reverse mapping data.
- Colocated test files.
- 25 new reverse map tests.

### v0.32.0 (2026-07-27)

- renderType table-driven refactor.
- PassContext read/write runtime validation.
- CLI command registry.

### v0.31.0 (2026-07-27)

- PassAccess runtime enforcement.
- DialectBackend optional method comptime checks.
- Reverse engineering confidence system.
- SARIF output.
- `rune docs` command.
- Import search paths.

### v0.30.0 (2026-07-27)

- DialectBackend vtable reorganization.
- Import parse cache.
- PassAccess declarations.
- Stdin pipeline tests.

### v0.11.0 – v0.29.0

- Schema import/include.
- Migration rollback.
- Virtual/generated columns.
- JSON Schema output.
- Diff/migrate CLI flags.
- Validate subcommand.
- Benchmark infrastructure.

### v0.1.0 – v0.10.0

- Core forward pipeline (`.ss` → SQL).
- Four dialect backends (MySQL, PostgreSQL, SQLite, MSSQL).
- Reverse engineering.
- Diff engine.
- Migration generation.
- Template system.
- CHECK constraints, indexes, foreign keys.
- Custom types.

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1: Core Solidification | ✅ Complete | 9/9 | 0 |
| 2: Extended Dialect Support | ✅ Complete | 14/14 | 0 |
| 3: ORM & API Schema Output | ✅ Complete | 13/15 | 2 (plugin system, template overrides) |
| 4: Incremental & Live Workflows | 🔲 Not started | 0/10 | 10 |
| 5: Developer Experience | 🟡 Partial | 3/12 | 9 |
| 6: Ecosystem & Community | 🔲 Not started | 0/9 | 9 |
| Architecture Targets | 🟡 Ongoing | 8/12 | 4 |
| **Total** | | **47/81** | **34** |
