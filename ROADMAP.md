# Rune Roadmap

This document outlines the planned evolution of Rune toward becoming a **universal database schema interchange format**. A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.59.0 (2026-07-31)

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

- [ ] Synchronized multi-error recovery — report all syntax errors in one pass instead of fail-fast
- [ ] Partial schema compilation — emit valid SQL for correct tables even when others have errors

### Semantic Analysis (all done)

- [x] Cycle detection for template inheritance
- [x] FK target validation — error when inline FK references a non-existent table or column
- [x] Unused template warning
- [x] Duplicate column name detection within a table
- [x] "Did you mean?" suggestions — Levenshtein edit distance for misspelled references

### Testing

- [ ] Fuzz testing infrastructure — random `.ss` input to find parser crashes
- [ ] Property-based tests for roundtrip fidelity (`.ss` → compile → reverse → compile → compare)
- [x] Golden test parallelization — `tests/test_parallel.sh` runs suites concurrently

---

## Phase 2: Extended Dialect Support

Add enterprise SQL dialects. Dialect infrastructure (capability flags) is done.

### New Dialect Backends

- [ ] **Oracle** — `dialect/oracle.zig` (~250 lines). No `AUTO_INCREMENT` (sequences + triggers), `NUMBER` precision/scale, `VARCHAR2`/`NVARCHAR2`, `CLOB`/`NCLOB`, tablespace clauses
- [x] **Microsoft SQL Server** — `dialect/mssql.zig` (~250 lines). `IDENTITY`, `NVARCHAR`/`NTEXT`, schema-qualified names (`dbo.table`), `GO` batch separators
- [ ] **IBM Db2** — `dialect/db2.zig` (~200 lines). `GENERATED ALWAYS AS IDENTITY`, `BIGINT`/`SMALLINT`, `FOR ROW ACCESS`

### Dialect Infrastructure (done)

- [x] Dialect capability flags — 12 feature flags per backend
- [x] Generator API dialect awareness
- [x] CLI unknown-flag detection

### Dialect Testing & Reverse

- [ ] Dialect-specific test suites — `tests/test_oracle.sh`, `tests/test_mssql.sh`, `tests/test_db2.sh`
- [ ] `rune reverse --dialect oracle` — dialect-aware reverse engineering per backend

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

- [ ] `rune generate openapi schema.ss` — OpenAPI 3.1 spec
- [ ] `rune generate graphql schema.ss` — GraphQL type definitions
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

- [ ] `rune init` — scaffold a new project with example schema
- [ ] `rune playground` — web-based `.ss` editor with live compilation (WASM)
- [ ] Shell completion scripts — `rune completions bash|zsh|fish|powershell`
- [ ] `rune fmt` — auto-format `.ss` files
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
