# Rune Roadmap

This document outlines the planned evolution of Rune toward becoming a **universal database schema interchange format**. A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.45.0 (2026-07-29)

---

## Phase 1: Core Solidification (v0.38 – v0.40)

Polish the existing foundation before expanding outward.

### Parser & Error Recovery

- [ ] Synchronized multi-error recovery — report all syntax errors in one pass instead of fail-fast
- [ ] Partial schema compilation — emit valid SQL for correct tables even when others have errors

### Semantic Analysis

- [x] Cycle detection for template inheritance (detected in `semantic/template.zig` during resolution)
- [x] FK target validation — error when inline FK references a non-existent table or column
- [x] Unused template warning — warn when a template is defined but never referenced
- [x] Duplicate column name detection within a table
- [x] "Did you mean?" suggestions — Levenshtein edit distance for misspelled FK table references and index column references

### Testing

- [ ] Fuzz testing infrastructure — random `.ss` input to find parser crashes
- [ ] Golden test parallelization — run suites concurrently in CI
- [ ] Property-based tests for roundtrip fidelity (generate `.ss` → compile → reverse → compile → compare)

---

## Phase 2: Extended Dialect Support (v0.40 – v0.45)

Add the most-requested enterprise SQL dialects.

### New Dialect Backends

- [ ] **Oracle** — `dialect/oracle.zig` (~250 lines). Challenges: no `AUTO_INCREMENT` (use sequences + triggers), `NUMBER` precision/scale semantics, `VARCHAR2`/`NVARCHAR2`, `CLOB`/`NCLOB`, tablespace clauses
- [ ] **Microsoft SQL Server** — `dialect/mssql.zig` (~250 lines). Challenges: `IDENTITY` instead of `AUTO_INCREMENT`, `NVARCHAR`/`NTEXT`, schema-qualified names (`dbo.table`), `GO` batch separators
- [ ] **IBM Db2** — `dialect/db2.zig` (~200 lines). Challenges: `GENERATED ALWAYS AS IDENTITY`, `BIGINT`/`SMALLINT` mapping, `FOR ROW ACCESS` control

### Dialect Infrastructure

- [x] Dialect capability flags — let each backend declare what it supports (SEQUENCES, SCHEMAS, TABLESPACES) so the parser can emit targeted warnings
- [ ] Dialect-specific test suites — `tests/test_oracle.sh`, `tests/test_mssql.sh`, `tests/test_db2.sh`
- [ ] `rune reverse --dialect oracle` — dialect-aware reverse engineering for each new backend

---

## Phase 3: ORM & API Schema Output (v0.45 – v0.50)

Bridge the gap between database schema and application code.

### ORM Generators

- [ ] `rune generate prisma schema.ss` — output Prisma schema files with models, fields, relations, and enums
- [ ] `rune generate drizzle schema.ss` — output Drizzle ORM TypeScript schema
- [ ] `rune generate typeorm schema.ss` — output TypeORM entity classes
- [ ] `rune generate sqlalchemy schema.ss` — output SQLAlchemy ORM models
- [ ] `rune generate knex schema.ss` — output Knex migration files

### API Schema

- [ ] `rune generate openapi schema.ss` — OpenAPI 3.1 spec with request/response schemas derived from tables
- [ ] `rune generate graphql schema.ss` — GraphQL type definitions from tables
- [ ] `rune generate json-schema schema.ss` — enhanced JSON Schema output (currently partial, needs `definitions`, `$ref`, proper `required` arrays)

### Generator Infrastructure

- [x] `rune generate --list` — show available generators
- [x] Generator registry — pluggable `Generator` struct with `REGISTRY` array in `generator.zig`
- [ ] Generator plugin system — allow user-defined generators via Zig plugins or WASM modules
- [ ] Template overrides — let users customize generator output with `.rune-template` files

---

## Phase 4: Incremental & Live Workflows (v0.50 – v0.55)

Move from batch compilation to interactive, incremental usage.

### Incremental Migration

- [ ] `rune migrate --incremental old.ss new.ss` — only emit SQL for tables that actually changed
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

## Phase 5: Developer Experience (v0.55 – v0.60)

Make Rune delightful to use day-to-day.

### LSP Language Server

- [ ] `rune-lsp` — standalone language server binary
- [ ] Completion — type symbols (`n`, `s32`, `m`), modifiers (`++`, `!`, `*`), keywords
- [ ] Diagnostics — real-time error/warning display as you type
- [ ] Go-to-definition — navigate from FK reference to target table/column
- [ ] Hover — show SQL type equivalent for SS symbols
- [ ] Code actions — quick fixes for common errors (add missing `++`, fix typo in symbol)
- [ ] Document symbols — outline view for tables, templates, views

### Editor Integration

- [ ] VS Code extension — syntax highlighting, completion, diagnostics, commands
- [ ] Neovim plugin — LSP-based with Treesitter grammar
- [ ] JetBrains IDE plugin — IntelliJ-based schema editor

### CLI Improvements

- [ ] `rune init` — scaffold a new project with directory structure and example schema
- [ ] `rune playground` — open a web-based `.ss` editor with live compilation (WASM)
- [ ] Shell completion scripts — `rune completions bash|zsh|fish|powershell`
- [ ] `rune fmt` — auto-format `.ss` files (consistent spacing, ordering, comments)
- [ ] colored output — syntax-highlighted SQL and diff output in terminal

---

## Phase 6: Ecosystem & Community (v0.60+)

Build the community and ecosystem around Rune.

### Distribution

- [ ] Package managers — `brew install rune`, `scoop install rune`, `apt`/`yum` repos
- [ ] npm package — `npx rune schema.ss` for Node.js workflows
- [ ] Docker image — `ghcr.io/rune-lang/rune:latest`
- [ ] Zig package manager — `build.zig.zon` for dependency consumption

### Documentation

- [ ] Interactive tutorial — web-based walkthrough with live examples
- [ ] Migration guide — from SQL DDL, Prisma, Knex to Rune `.ss`
- [ ] Cookbook — common patterns (multi-tenant, soft delete, audit trail, tree structures)
- [ ] Video walkthroughs — schema design, migration, CI/CD integration

### Community

- [ ] RFC process — formal proposal mechanism for language changes
- [ ] Schema registry — shared template library (pagination, user auth, common patterns)
- [ ] Playground sharing — share `.ss` snippets via URL

---

## Architecture Targets

These are ongoing architectural improvements to pursue alongside feature work.

### Performance

- [ ] Streaming compilation — output SQL as soon as each table is resolved (currently waits for full AST)
- [ ] Parallel table compilation — compile independent tables concurrently
- [ ] Memory-mapped file I/O — for large schema files (>10MB)
- [ ] Benchmark CI gate — enforce no regressions beyond 10% (currently 20%)

### Code Quality

- [x] Remove all `catch unreachable` in production code — replaced with proper error propagation (v0.39.0)
- [ ] Zero-allocation codegen path — reuse buffers across compilations
- [ ] Audit all `@intCast` / `@enumFromInt` for safety in debug builds
- [ ] Formalize IR versioning — schema for forward/backward compatibility across Rune versions

### Platform

- [ ] Cross-compile to WASM — enable browser and Deno usage
- [ ] Windows native builds — test and document MSVC/MinGW paths
- [ ] ARM64 CI — test on Apple Silicon and ARM Linux

---

## Completed

### v0.45.0 (2026-07-29)

- DialectCapability system — 12 feature flags per dialect backend, enabling feature-aware codegen and parser warnings
- CompileConfig struct — replaced 13-parameter handleCompileRequest with named-field config struct
- Generator API dialect awareness — generate() now receives dialect parameter for dialect-specific output
- CLI unknown-flag detection — unrecognized --flags produce error with flag name
- Allocator consistency — replaced page_allocator with arena/stack allocation in edit_distance, diagnostic, pass_manager
- 5 new io.zig unit tests
- Updated 247 golden test files from 0.44.0 to 0.45.0

### v0.43.0 (2026-07-29)

- Generator registry — pluggable `Generator` struct with `REGISTRY` array in `generator.zig`, replacing hardcoded dispatch in `main.zig`
- Fixed memory leak in `detectConflicts()` — accepts `Allocator` parameter instead of using `page_allocator` directly
- Fixed memory leak in `transitiveDependsOn()` — added `defer` cleanup for `BufSet` and `ArrayList`
- Parallel golden test runner — `tests/test_parallel.sh` runs 12 test suites concurrently
- Updated golden test files from version 0.42.0 to 0.43.0 (244 files)

### v0.42.0 (2026-07-29)

- Fixed buffer overflow risk in `reverse/map.zig` — added bounds checking for decimal/numeric parameterized type patterns
- Extracted `hasChanges()` method on `SchemaDiff` — eliminates 3x duplicated check blocks in `pipeline/diff.zig`
- Added `rune generate` subcommand with JSON Schema generator support
- Added `rune generate --list` to show available generators
- Added 8 new unit tests (types_test.zig: 3, map_test.zig: 2, existing tests updated)

### v0.41.0 (2026-07-29)

- DiagnosticCollector error count caching — O(1) `errorCount()` instead of O(n) scan
- Replaced `std.debug.panic` with proper error return in semantic analyzer pass constraint validation
- Added doc comments to public APIs (io.zig, pipeline/diff.zig, pipeline/reverse.zig, codegen/codegen.zig, diff/engine.zig, diff/migrate.zig, reverse/codegen.zig)
- Added 10 unit tests for `docs.zig` (documentation generator)
- Added 18 unit tests for `diff/migrate_json.zig` (JSON migration output)
- Total unit tests: 499 → 526

### v0.40.0 (2026-07-29)

- Fixed memory leaks across diff subsystem — hash maps, ArrayLists, and intermediate allocations properly freed
- Replaced `ArrayList.toOwnedSlice(alloc)` with safe `dupe + deinit` pattern in diff engine to prevent buffer leaks
- Fixed `validate` vs `check` CLI behavior — `validate` always succeeds, `check` exits 1 on errors
- Fixed redundant allocations in 8 production files — `aw.toOwnedSlice()` instead of `aw.toArrayList().toOwnedSlice(alloc)`
- Fixed error message to include SARIF in unknown format error
- Memory leaks reduced from 606 to 533 (73 fewer)

### v0.39.0 (2026-07-29)

- Unused template warning — emit warning when a template is defined but never referenced by any table or other template
- "Did you mean?" suggestions — Levenshtein edit distance for misspelled FK table references and index column references
- Fixed `catch unreachable` in pass_manager.zig and validate_template_types.zig
- Added `utils/edit_distance.zig` with Levenshtein distance and closest-match suggestion
- Extended PassContext with `template_refs` for unused template tracking
- 15 new unit tests (484 → 499 total)

### v0.38.0 (2026-07-28)

- Fixed ast_visitor_test.zig broken callbacks + memory leaks (24 fails → 23, 592 leaks → 564)
- Fixed FK rename buffer overflow (dynamic allocation instead of fixed [8])
- Fixed PG ALTER TABLE index emission (standalone CREATE INDEX instead of comment)
- Fixed FK constraint name separator in MySQL/PostgreSQL

### v0.37.0 (2026-07-28)

- Fixed colocated test compilation (72 errors)
- Added `--json-errors` flag for CI/CD integration
- Added `rune check` subcommand

### v0.36.0 (2026-07-28)

- Comptime RenderEntry validation
- TypedAst `ss_symbol` cleanup
- Diff FK rename detection
- Shared test helpers extraction

### v0.35.0 (2026-07-28)

- Re-enabled colocated test files
- Fixed 9 compilation errors across test files
- Added `tests.zig` module index

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
- Three dialect backends (MySQL, PostgreSQL, SQLite)
- Reverse engineering
- Diff engine
- Migration generation
- Template system
- CHECK constraints, indexes, foreign keys
- Custom types

---

## Legend

- [ ] Planned — not yet started
- [x] Done — shipped in a release
- Priority is top-down within each phase, but phases overlap in practice
- Version numbers are approximate — shipped when ready, not by deadline
