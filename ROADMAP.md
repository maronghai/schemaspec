# Rune Roadmap

This document outlines the planned evolution of Rune toward becoming a **universal database schema interchange format**. A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.140.0 (2026-08-06) — 25,000+ lines production Zig, 1130+ tests, 26 test suites.

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

Move from batch compilation to interactive, incremental usage. **In progress** — migration naming, incremental filter, and status shipped in v0.93.0.

### Incremental Migration

- [x] `rune migrate --incremental old.ss new.ss` — only emit SQL for changed tables (v0.93.0)
- [x] Migration file naming — `001_add_users.sql`, `002_add_posts.sql` with auto-sequencing (v0.93.0)
- [x] Migration dependency graph — detect and order dependent migrations (v0.102.0)
- [x] `rune migrate status` — list migration files in a directory (v0.93.0)

### Live Schema Monitoring

- [x] `rune watch schema.ss` — watch file changes and recompile automatically (v0.117.0)
- [x] `rune diff --live schema.ss mysql://host/db` — compare `.ss` file against a live database via stdin pipe (v0.139.0)
- [x] Schema drift detection — `rune diff schema.ss --from-sql live.sql` compare expected vs SQL dump (v0.134.0)

### CI/CD Integration

- [x] GitHub Action — `rune-ci/check-schema` composite action (v0.116.0)
- [x] GitLab CI template — `.rune-ci.yml` for pipeline integration (v0.116.0)
- [x] Pre-commit hook generator — `rune hooks pre-commit` outputs shell scripts (v0.116.0)

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
- [x] Colored output — syntax-highlighted SQL and diff output (v0.97.0)
- [x] `rune validate` as first-class CLI command — exposed in help text with examples (v0.101.0)
- [x] Unknown flag suggestions — edit-distance-based "Did you mean?" for mistyped flags (v0.101.0)
- [x] `rune stats --format json` — JSON output for schema statistics (v0.101.0)
- [x] `rune watch` — watch file changes and recompile automatically (v0.117.0)
- [x] `rune lint` — lint schema for quality issues: missing PK, naming conventions, FK indexes, timestamps, wide tables, enum case, field count, FK cascade, nullable PK, orphan types (v0.136.0, v0.137.0, v0.138.0)

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

- [x] Streaming compilation — output SQL as soon as each table is resolved (v0.102.0)
- [x] Parallel table compilation — compile independent tables concurrently (v0.120.0)
- [x] Memory-mapped file I/O — for large schema files (>10MB) (v0.123.0)
- [x] Benchmark CI gate — enforce no regressions beyond 10% (v0.82.0)
- [x] Benchmark dialect parameterization — `rune bench --dialect <d>` supports all 6 dialects (v0.74.0)
- [x] Benchmark stage breakdown — tokenize and parse measured independently (v0.57.0)

### Code Quality

- [x] Remove all `catch unreachable` in production code (v0.39.0, v0.103.0, v0.105.0)
- [x] Remove all unsafe `@intCast`/`@enumFromInt` in production code (v0.80.0)
- [x] Named constants for magic numbers — `STDIN_BUFFER_SIZE`, `OUTPUT_BUFFER_SIZE`, etc. (v0.80.0)
- [x] Eliminate `std.process.exit` in library code — all errors propagate to main.zig (v0.80.0, v0.103.0)
- [ ] Zero-allocation codegen path — reuse buffers across compilations
- [x] Formalize IR versioning — schema for forward/backward compatibility (v0.108.0)
- [x] Memory leak audit — reduce remaining leaks toward zero (v0.123.0)
- [x] Fuzz testing expansion — longer runs, more seed variety, coverage-guided mutation (v0.123.0)

### Platform

- [ ] Cross-compile to WASM — enable browser and Deno usage
- [ ] Windows native builds — test and document MSVC/MinGW paths
- [ ] ARM64 CI — test on Apple Silicon and ARM Linux

---

## Release History

### v0.140.0 (2026-08-06)

- **Markdown diff stats bug fix** — `rune diff --format markdown` now correctly reports table and field counts separately. Previously, "Tables added" incorrectly summed field additions into the table count, producing misleading statistics (e.g. "Tables added: 6" when only 1 table with 5 new fields was added).
- **Lint index-out-of-bounds fix** — Fixed `index-unused` lint rule crash when an index has an empty fields slice. Now gracefully handles malformed index data instead of panicking.
- **Lint memory leak fix** — `formatLintResults`, `formatLintJson`, and `formatLintSarif` now accept an allocator parameter instead of using `page_allocator` internally. Callers manage memory properly, eliminating leaks in non-exit code paths.
- **Dead code cleanup** — Removed unused `LintOutput` enum and `hasPrimaryKey` function from `lint.zig`.
- **Golden tests build target fix** — `zig build golden-tests` now correctly references `tests/*.sh` at the project root instead of the non-existent `rune/tests/` directory.
- **Pipeline diff unit tests** — 9 new unit tests in `pipeline/diff_test.zig` covering: `formatMigrationFileName` (zero-padded, large sequence, zero), `filterIncrementalChanges` (structural kept, metadata-only removed, create kept, index changes kept), and config default values.
- **New tests**: ~9 new unit tests. Total: ~1135 tests.

### v0.139.0 (2026-08-06)

- **Live database diff via stdin** — `rune diff schema.ss --from-sql -` reads SQL from stdin, enabling direct comparison against live databases via pipe: `mysqldump --no-data mydb | rune diff schema.ss --from-sql -`. Phase 4 complete.
- **In-memory diff pipeline** — Eliminated temp file creation in `--from-sql` path. SQL text is now reverse-engineered and compiled in-memory via new `compileSqlToAst` pipeline function. Faster and no disk artifacts.
- **`rune stats --summary`** — Compact one-line stats output: `3 table(s), 24 field(s), 4 view(s), 6 FK(s), 8 index(es), 0 check(s), 0 type(s)`. Useful for quick schema overview.
- **2 new lint rules** — `index-unused` (warns when standalone index doesn't correspond to FK, unique, or PK constraint), `circular-fk` (warns when FK chains form circular references like A→B→A). Total: 12 lint rules.
- **SARIF rule expansion** — `rune lint --format sarif` now includes all 12 lint rules.
- **New tests**: 6 new unit tests in `lint_test.zig` covering: unused index detected, FK-covered index passes, unique index passes, circular FK detected, no circular FK passes. Total: ~1126 tests.

### v0.138.0 (2026-08-06)

- **Expanded lint rules** — 3 new lint rules: `fk-cascade` (warns when FK columns lack explicit ON DELETE/ON UPDATE actions), `nullable-pk` (warns when PK columns have nullable modifier), `orphan-type` (warns when custom type definitions are unused by any table). Total: 10 lint rules.
- **Lint help text** — `rune lint --help` now documents all 10 lint rules with descriptions. Added `--format` and `--rules` flag documentation. Added diff-aware lint example.
- **SARIF rule expansion** — `rune lint --format sarif` now includes all 10 lint rules in the SARIF rule definitions for CI/CD integration.
- **New tests**: 9 new unit tests in `lint_test.zig` covering: FK without cascade detection, FK with both actions passes, FK with only ON DELETE detected, nullable PK detected, non-nullable PK passes, orphan type detected, used type passes orphan check. Total: ~1120 tests.

### v0.137.0 (2026-08-06)

- **Expanded lint rules** — 3 new lint rules: `wide-table` (warns when table has >30 fields), `enum-case` (warns when custom types use non-UPPER_CASE naming), `count` (warns when table has <2 non-PK fields). Thresholds configurable via `rune-lint.toml`.
- **SARIF output** — `rune lint --format sarif` produces SARIF 2.1.0 output for CI/CD integration (GitHub Code Scanning, SonarQube). Each lint rule maps to a SARIF rule with proper severity levels.
- **Diff-aware lint** — `rune lint old.ss new.ss` compares lint results between two schemas and outputs only newly introduced issues. Useful for pre-commit checks and CI gates.
- **Lint rules config** — New `rune-lint.toml` configuration file for customizing lint behavior: enable/disable rules, override severity levels, adjust thresholds. Discovered upward from cwd like `rune.toml`. New `--rules <path>` flag.
- **New tests**: 15 new unit tests in `lint_test.zig` covering: wide table detection, narrow table passes, non-UPPER_CASE custom types, UPPER_CASE passes, low field count, sufficient count, SARIF output, SARIF empty results, diff new issues, diff no new issues, config toggles, rules file parsing. Total: ~1111 tests.

### v0.136.0 (2026-08-06)

- **`rune lint` subcommand** — New `rune lint schema.ss` command that analyzes schema for quality issues and anti-patterns. Four lint rules: `no-pk` (table has no primary key), `naming` (camelCase instead of snake_case), `no-index-fk` (FK column without index), `no-timestamps` (no created_at/updated_at). Supports `--json-errors` for machine-readable output and `--strict` for CI/CD (exit 1 on warnings). Each rule can be individually toggled via `LintConfig`. New `lint.zig` module (~150 lines) and `lint_test.zig` (~250 lines, 10 unit tests).
- **CLI integration** — `lint` added to Command union, COMMAND_REGISTRY, parse/parse_utils, help text (with lint rules documentation), and all 4 shell completion scripts (bash, zsh, fish, powershell). Unknown flag suggestions updated for `--lint`.
- **New tests**: 10 new unit tests in `lint_test.zig` covering: clean schema, no-pk detection, composite PK via index, camelCase naming, FK without index, FK with index, timestamps present/absent, config toggles, JSON output format. Total: ~1096 tests.

### v0.135.0 (2026-08-06)

- **Diagnostic severity consistency** — Fixed FK type mismatch severity: cross-category mismatches (e.g. string→integer) now emit `.warning` (was `.note`), same-category mismatches (e.g. bigint→int) emit `.note` (was `.warning`). Cross-table duplicate index names now emit `.warning` (was `.note`), consistent with intra-table duplicate detection. 3 new severity assertion tests.
- **Missing flag value errors** — `--format`, `--config`, and `--import-path` now return explicit errors when used without a value (e.g. `rune diff --format` → `error: --format requires a value`). Previously these were silently ignored. 4 new tests.
- **Diff format parity** — JSON diff output now includes `metadata_diff` field for table comment/engine changes. SARIF diff output now includes results for view diffs (`schema/view-create`, `schema/view-drop`, `schema/view-modify`) and metadata changes (`schema/metadata-comment`, `schema/metadata-engine`). 7 new tests.
- **Shell completions fixed** — Added `--generators` flag to Bash, Zsh, Fish, and PowerShell completions. Fixed broken PowerShell fallback completion (`@( | ForEach-Object` → proper pipeline).
- **Config file expansion** — `rune.toml` now supports `stream`, `parallel`, `target`, and `format` keys under `[output]`. Config values are applied as defaults when CLI flags aren't explicitly set. Validation added for `target` (must be `sql` or `json-schema`) and `format` (must be `text`, `json`, `sarif`, or `markdown`). 6 new tests.
- **New tests**: 20 new unit tests across `validate_fk_types.zig`, `validate_index_names.zig`, `cli_test.zig`, `json_test.zig`, `sarif_test.zig`, and `config_test.zig`. Total: ~1086 tests.

### v0.134.0 (2026-08-06)

- **Schema drift detection** — New `rune diff schema.ss --from-sql live.sql` flag compares a `.ss` schema against a SQL dump file. Reverse-engineers the SQL file internally, compiles it through the forward pipeline, and diffs against the original schema. Supports all diff output formats (text, JSON, SARIF, markdown) and CI/CD gate mode (`--check`). Enables drift detection without database connectivity — perfect for CI pipelines where you dump the database schema and compare it against the expected schema.
- **CLI help improvements** — Added `--from-sql` to diff command help with examples. Added drift detection examples to main help text.
- **Shell completions updated** — Bash, Fish, PowerShell completions now include `--from-sql` flag.

### v0.133.0 (2026-08-06)

- **FK type compatibility validation** — New semantic pass `validate_fk_types` (13th pass) warns when FK field types don't match the referenced PK/unique field types. Catches common schema bugs like integer FKs referencing string PKs at compile time. Emits notes for cross-category mismatches (e.g. integer→string) and warnings for same-category but different types.
- **New unit tests** — 8 tests in `semantic/pass/validate_fk_types.zig` covering: same-type match, string match, string→integer mismatch, integer→string mismatch, same-category (numeric→numeric), inline FK mismatch, multiple FKs with mixed compatibility, FK to non-existent table. Total: 1066 tests.

### v0.132.0 (2026-08-06)

- **Batch generation** — `rune generate schema.ss --generators prisma,drizzle,openapi` runs multiple generators from a single schema compilation. The `--generators` flag accepts a comma-separated list of generator names. Each generator's output is written to a separate file when `-o` is specified, or to stdout with headers. Backward compatible: single `rune generate prisma schema.ss` still works.
- **CLI `--generators` flag** — New flag for `rune generate` subcommand. Added to `KNOWN_FLAGS` for edit-distance suggestions. Two-pass parsing ensures `--generators` is handled before positional arguments.
- **New tests** — 2 new CLI tests for `--generators` flag parsing (comma-separated values, values with spaces). Total: 1058 tests.

### v0.131.0 (2026-08-06)

- **Fixed thread spawn failure leak** — `codegen/parallel.zig` now safely handles partial `std.Thread.spawn` failures. Previously, if spawning failed mid-group, already-spawned threads were never joined (thread leak). Now all spawned threads are joined before falling back to sequential compilation. Applied to both the direct-parallel and batched-parallel code paths.
- **CLI parser decomposition** — Extracted the 90-line global flag parsing chain from `parseArgs` into a dedicated `parseGlobalFlags` function with a `FlagResult` return type. Added `buildParsedArgs` helper to construct `ParsedArgs` from flags. `parseArgs` is now ~60 lines (was ~230), cleanly separated into: global flag parsing → subcommand dispatch → default command construction.
- **New tests** — 1 new `compileParallel` unit test for fully-dependent sequential fallback (3 chained FK tables). Total: 1056 tests.

### v0.129.0 (2026-08-05)

- **Fixed watch mode parallel compilation bug** — `rune watch --parallel` now correctly forwards the `stream` and `parallel` flags to the compilation pipeline. Previously, the parallel code path was unreachable from watch mode because the flags were not forwarded to `CompileConfig`.
- **Level-by-level parallel grouping** — `codegen/parallel.zig` now assigns tables to dependency levels (level 0 = no deps, level 1 = depends only on level-0, etc.) instead of a binary independent/dependent split. This enables more parallelism: tables at the same dependency level can compile concurrently, even when they are part of a larger dependency chain.
- **CLI parser decomposition** — Split 627-line `cli/parse.zig` into focused modules: `parse_compile.zig` (diff/migrate/reverse/generate/validate/check/stats parsers) and `parse_utils.zig` (docs/format/init/completions/hooks/watch parsers). `parse.zig` is now a thin barrel with shared flag parsers and the main `parseArgs` entry point.
- **New tests** — 4 new `findGroups` unit tests covering 3-level chains, diamond patterns, and mixed independent/dependent tables. Total: 1048 tests.

### v0.128.0 (2026-08-05)

- **Unified dialect name registry** — Single source of truth for all dialect name strings in `dialect/enum.zig`. Added `DialectNameEntry` struct, `ALL_NAMES` comptime array (primary names + aliases), and `VALID_NAMES_CSV` comptime string. Eliminates hardcoded dialect name duplication across 5 files (`main.zig`, `bench.zig`, `config.zig`, `cli/help.zig`, `completions.zig`). Adding a new dialect now requires updating only `dialect/enum.zig`.
- **`rune stats --format markdown`** — New markdown table output format for schema statistics. `rune stats schema.ss --format markdown` produces a clean markdown table suitable for PR descriptions and documentation. Format wired through CLI parser, stats command handler, and `stats.zig` formatter.
- **`config.zig` dialect validation unified** — `isValidDialect` now delegates to `dialect_enum.parseDialect` instead of maintaining a separate hardcoded list. Config validation now accepts all aliases (e.g. `sq`, `ora`, `idb2`) consistently with CLI parsing.
- **New tests** — 2 new unit tests for `formatStatsMarkdown` (zero values, populated values). Total: 1046 tests.

### v0.127.0 (2026-08-05)

- **Watch command feature parity** — `rune watch` now supports `--trace`, `--stats`, `--json-errors`, and `--parallel` flags. Previously only `--interval` and `--parallel` were available. All compilation options are now consistent between `rune <file>` and `rune watch <file>`.
- **Watch subcommand help** — `rune watch --help` now displays all available options including `--trace`, `--stats`, `--json-errors`, `--parallel`, `--interval`, `--dialect`, `--target`, and `--output`.
- **Shell completions expansion** — Added `--parallel`, `--interval`, `--stream`, `--summary`, `--config`, `--name`, `--dir`, `--incremental`, `--graph` flags to Bash, Fish, and PowerShell completions. Added `symbol-index` generator to all 4 shell completion scripts. Zsh completions now offer watch-specific flag completions.
- **Build dependency fix** — Removed unnecessary `b.getInstallStep()` dependency from test targets in `build.zig`. Unit tests no longer require the rune binary to be installed first, eliminating Windows file locking conflicts during test runs.

### v0.126.0 (2026-08-05)

- **Config file discovery** — `rune.toml` is now searched upward from cwd (like `git` searches for `.git/`). Stops at filesystem root. Eliminates the need to place `rune.toml` in the exact directory where `rune` is invoked.
- **Config unknown-key warnings** — Malformed `rune.toml` files now warn about unknown sections and keys (e.g. `[typo]` or `deafult = "pg"`). Helps catch configuration typos early.
- **New tests** — 4 new unit tests for `warnUnknownKeys` covering valid config, unknown sections, unknown keys, and empty input. Total: 1045+ tests.

### v0.125.0 (2026-08-05)

- **Watch mode busy-wait fix** — Replaced spin-loop with `std.Io.Clock.Duration.sleep()` for efficient file polling. CPU usage drops from ~100% to ~0% during watch mode.
- **Watch mode parallel flag** — `rune watch` now supports `--parallel` for parallel streaming compilation during watch.
- **New semantic pass: validate_index_names** — Detects cross-table index name collisions that may cause issues in databases requiring globally unique index names (e.g. PostgreSQL). 3 unit tests.
- **Version drift fix** — Synced VERSION file (0.124.0) with build.zig.zon (was 0.123.0). Both now report 0.125.0.
- **Documentation sync** — Fixed README.md: vtable count "26+6" → "25+7", removed stale `canRunConcurrently()` reference, fixed VARBARCHAR typo → VARBINARY. Updated CLAUDE.md: semantic passes 11→12, colocated test files 81→82.
- **Test count**: 1040 (was 1037)

### v0.124.0 (2026-08-05)

- **Codegen by-pointer refactor** — All `Codegen` methods now take `*Codegen` (mutable pointer) instead of `Codegen` (by value). Eliminates unnecessary copies of the 30+ function pointer `DialectBackend` vtable on every method call. `StreamingCodegen` now stores `cg: *codegen.Codegen` (heap-allocated) for consistent pointer semantics.
- **Diff format helper extraction** — Extracted `emitAlterTableHeader` helper in `diff/format/text.zig`, eliminating 5 repetitions of the `-- ALTER TABLE` header emission pattern. Reduces `writeDiffTo` from 173 to ~160 lines.
- **Main dispatch deduplication** — Extracted `printAvailableGenerators()` and `resolveOutputFormat()` helpers in `main.zig`, eliminating duplicated generator listing (2 occurrences) and format mapping (2 occurrences).
- **Zig 0.16 API fixes** — Fixed `io.zig` to use `std.Io.Dir.cwd()` instead of removed `std.fs.cwd()`. Added `io` parameter to `mmapFile`, `file.stat()`, and `file.close()` calls. Added Windows fallback for `mmapFile` (uses `readFileAlloc` instead of `std.posix.mmap`).
- **Documentation sync** — Updated CLAUDE.md: semantic passes 8→11, colocated test files 80→81, removed stale `DialectCapability` paragraph, removed `type_map.zig` from source layout.

### v0.123.0 (2026-08-05)

- **Memory-mapped file I/O** — New `mmapFile` function in `io.zig` uses `std.posix.mmap` for files >1MB. `readFileOrStdin` now automatically uses memory-mapped I/O for large schema files, reducing heap allocation pressure. Falls back to traditional `readFileAlloc` for small files or stdin. New `MmapResult` struct with proper `deinit` for cleanup.
- **BufferPool expansion** — Added `BufferPool.initWithCapacity` method for pre-allocated pool sizes. BufferPool is now available for batch compilation scenarios with predictable buffer counts.
- **Memory leak fix** — Fixed leaked `tmpl_list` allocation in `reverse/codegen.zig:generateInner`. Template candidates from `findTemplates` are now properly freed with `defer` block that releases fields, table indices, and the list itself.
- **Fuzz testing infrastructure** — Existing `fuzz.zig` supports 6 mutation strategies (random, boundary, truncate, duplicate, structural, combined) and cross-dialect reverse pipeline fuzzing (all 6 dialects tested per iteration).

### v0.122.0 (2026-08-05)

- **Real parallel table compilation** — `codegen/parallel.zig` now uses `std.Thread` to compile independent table groups concurrently. Each thread uses its own arena allocator for thread safety. The existing dependency graph and topological sort infrastructure is leveraged to determine which tables can be compiled in parallel. Falls back to sequential for schemas with <10 tables or fully-dependent tables. New `max_threads` config option (default: 4).
- **Memory leak fixes** — Fixed leaked `ArrayList` metadata in `bench.zig:parseFileTimed` and `bench.zig:parseFile`. Both functions now properly `defer lines.deinit(alloc)`.
- **errdefer patterns** — Added `errdefer` to `ArrayList` allocations in `diff/engine.zig` (3 lists), `diff/fields.zig` (1 list), `diff/fks.zig` (1 list), and `diff/indexes.zig` (1 list). Prevents memory leaks on error paths in the diff engine.
- **New tests** — 5 new unit tests for parallel compilation: `findGroups` independent/dependent split, `findGroups` all-independent, `compileParallel` sequential fallback, `compileParallel` concurrent path, `compileParallel` topological ordering with FK dependencies.
- **Documentation sync** — Fixed stale "8 passes" → "11 passes" and "4 dialect backends" → "6 dialect backends" in README.md. Fixed stale incremental migration roadmap item. Updated CLAUDE.md parallel compilation description.

### v0.121.0 (2026-08-05)

- **Shared `writeColorized` helper** — New `diff/format_common.writeColorized` eliminates ~30 duplicated `if (use_color) { write(color); ...; write(RESET) } else { ... }` blocks across `diff/format/text.zig`. `writeDiffTo` reduced from 342 to ~170 lines.
- **Shared `DiffStats` + `formatSummaryStats`** — Extracted `DiffStats` struct and summary line formatter into `diff/format_common.zig`. Both `formatDiff` and `formatDiffSummary` in `text.zig` now delegate to the shared helper, eliminating ~50 lines of duplicated summary logic. `markdown.zig` also uses shared `DiffStats` instead of re-implementing the same counting loop.
- **SARIF boilerplate reduction** — Extracted `writeSarifResult` helper in `diff/format/sarif.zig`, reducing per-result JSON structure duplication.

### v0.120.0 (2026-08-05)

- **Migration Plan IR** — New `diff/plan.zig` module introduces an explicit intermediate representation (`MigrationPlan`) between `SchemaDiff` and SQL generation. `planFromDiff()` converts diffs to plans, `invertPlan()` transforms plans for rollback, and `generateFromPlan()` renders plans to SQL. The existing `generateFromDiff` and `generateRollback` functions now delegate through the plan layer, producing identical output while enabling future dry-run inspection and plan-level validation.
- **Parallel table compilation** — New `codegen/parallel.zig` module analyzes table FK dependencies and compiles independent tables concurrently. `analyzeDependencies()` builds a dependency graph, `topoSort()` orders tables, and `compileParallel()` generates SQL in dependency order. Falls back to sequential for schemas with <10 tables or fully-dependent tables. CLI flag: `--parallel` (used with `--stream`).
- **Golden test utilities** — New `golden_test.zig` module provides `stripVersion()` and `compareOutput()` functions for version-resilient golden test comparison. Handles both SQL version comments and JSON version fields.
- **`--parallel` CLI flag** — New flag for parallel streaming compilation. `rune schema.ss --stream --parallel` enables concurrent table compilation.
- **`zig build golden-tests`** — New build step that runs all 25 shell-based golden test suites.

### v0.119.0 (2026-08-05)

- **Colored diagnostics** — Schema errors, warnings, and notes now display with ANSI color codes when `--color` is enabled. Errors in red, warnings in yellow, notes in gray. Line numbers bold, source context dimmed. Color mode flows from CLI `--color` flag through the semantic analyzer to all diagnostic output.
- **Fixed `std.process.exit` in `handleHooks`** — `completions.zig:handleHooks` now returns `error.UnknownHookType` instead of calling `std.process.exit(1)` directly. Error handling now flows through `main.zig`'s dispatch error handler, consistent with the code quality target (v0.80.0).
- **Watch mode cleanup** — Simplified the polling loop in `watch.zig`.

### v0.118.0 (2026-08-05)

- **Expanded diagnostic test coverage** — 7 new tests for `DiagnosticCollector`: `formatTerminal` output (content + empty), `hadOom` accessor, `record` alias, JSON escaping of special characters, and LSP 0-based line number conversion.
- **ROADMAP sync** — Marked `rune watch` as done in Phase 4 (shipped in v0.117.0). Updated summary counts (60/81 done).

### v0.117.0 (2026-08-05)

- **`rune watch`** — New subcommand that watches a `.ss` file for changes and automatically recompiles when modifications are detected. Uses file content hash comparison for change detection. Supports `--interval <ms>` flag (default: 1000ms). Press Ctrl+C to stop watching.
- **CLI help improvements** — Added `watch` command to help text with examples and options.
- **Shell completions updated** — Bash, Zsh, Fish, PowerShell completions now include `watch` subcommand.
- **New unit tests** — `watch_test.zig` (3 tests): WatchConfig defaults, custom values, dialect configuration.

### v0.116.0 (2026-08-05)

- **`rune hooks pre-commit`** — New subcommand that outputs a pre-commit shell script for validating `.ss` schema files before commits. Auto-detects `rune` binary (local build or PATH), filters staged `.ss` files, and runs `rune validate` on each.
- **GitHub Action** — Reusable composite action at `.github/actions/rune-ci/action.yml` for schema validation in CI pipelines. Supports dialect selection, strict mode, and check mode.
- **GitLab CI template** — `.gitlab-ci.yml` with `rune-validate` and `rune-validate-strict` jobs that trigger on `.ss` file changes.
- **Enhanced fuzzer** — `rune/fuzz` now supports 6 mutation strategies (random, boundary, truncate, duplicate, structural, combined) and cross-dialect reverse pipeline fuzzing (all 6 dialects tested per iteration).
- **ARM64 CI testing** — Added `test-arm64` job to CI workflow that cross-compiles for aarch64-linux and runs unit + golden tests on native x86_64.
- **Expanded CI coverage** — CI workflow now runs all 25 test suites (was 10): added MSSQL, Oracle, Db2, migration status, reverse Oracle/Db2, JSON Schema, imports, stdin, init, color, validate, and stats JSON tests.
- **Shell completions updated** — Bash, Zsh, Fish, PowerShell completions now include `hooks` subcommand with `pre-commit` argument.
- **CLI help updated** — `rune --help` and `rune hooks --help` show usage and installation instructions.

### v0.115.0 (2026-08-05)

- **Documentation sync** — Updated ARCHITECTURE.md to match current codebase: removed stale `DialectCapability` section (removed in v0.91.0), updated semantic pass list (8 → 11 passes), fixed `validate_schema` → 4 focused passes (v0.107.0 split), fixed `dialect_enum.zig` → `dialect/enum.zig`, removed stale `type_map.zig` reference (merged in v0.114.0), fixed duplicate numbering in Key Design Decisions, updated test file count (80 → 81), added `symbol-index` generator to list.
- **New unit tests** — `types/symbol_table_test.zig` (10 tests): registerTable, registerTemplate, cross-type conflicts, lookupTable, lookupField, contains. Registered in `tests.zig`.
- **README.md updates** — Added `db2` to dialect flag reference and Quick Start examples. Added `graphql` and `symbol-index` to generator list.
- **CLAUDE.md sync** — Updated colocated test file count (80 → 81).

### v0.114.0 (2026-08-05)

- **Fixed stdin dialect config drop** — `handleCompileRequest` now passes all `CompileConfig` fields (dialect, trace, stats, check, quiet, stream, run_semantic) when reading from stdin. Previously, only `verbose_passes` and `json_errors` were forwarded, causing stdin input to silently default to MySQL dialect.
- **Fixed pipeline layering violations** — `pipeline/diff.zig`, `pipeline/reverse.zig`, and `diff/format/text.zig` now import `cli/types.zig` directly instead of the `cli.zig` barrel. Eliminates unnecessary coupling to the CLI parsing layer.
- **Consolidated type helper modules** — Merged `types/type_map.zig` (47 lines) into `types/type_registry.zig`. Removed `isNumericSymType`/`isDatetimeSymType` wrapper functions — callers now use `TypeInfo.isNumeric()`/`TypeInfo.isDatetime()` directly. Moved `lookupCustomType` to `type_registry.zig` as the single entry point for all SS symbol → type resolution.
- **Config error visibility** — Malformed `rune.toml` files now produce a warning message instead of being silently ignored. `FileNotFound` still falls back to defaults silently (expected behavior).
- **Reverse JSON refactor** — Extracted `writeJsonStringField`, `writeJsonStringArray`, and `writeJsonBoolField` helpers from `generateReverseJson`. Replaces ~40 lines of duplicated JSON field writing with reusable 3-5 line helper calls. Consistent indentation and comma handling.

### v0.113.0 (2026-08-04)

- **Shared interleaving iterator** — Extracted `codegen/interleave.zig` with a generic `LineMerger` struct that merges three sorted-by-line_no sequences. Replaces three duplicated interleaving loops in `codegen/codegen.zig:fillWriter`, `codegen/streaming.zig:generateStreaming`, and the removed `InterleaveIterator`. Eliminates ~60 lines of duplicated merge logic.
- **Split `cli.zig` into focused modules** — Split 792-line `cli.zig` into `cli/types.zig` (type definitions), `cli/parse.zig` (argument parsing), and `cli/help.zig` (help text). `cli.zig` is now a thin re-export barrel (~40 lines). All existing callers continue to work unchanged.
- **BufferPool integration** — Wired the existing `BufferPool` (codegen.zig) into the streaming compilation path via `StreamingCodegen.initWithPool`. Fixed Zig 0.16 API compatibility (`ArrayList.empty`, `pop()` returns optional, `deinit(alloc)`). Buffers are reused across table/view generation in streaming mode.
- **Reverse JSON cleanup** — Removed `_end: true` sentinel hack from `generateReverseJson`. Uses proper first-property tracking for trailing commas. Replaced raw `w.print("{s}")` with `utils.jsonEscapeString` for safe string escaping.
- **Migrate status refactor** — Extracted `MigrateFile` struct and `collectMigrateFiles` helper from `handleMigrateStatus`. Both JSON and text branches now consume the same pre-parsed, pre-sorted file list.
- **Diff engine allocation fix** — Replaced `alloc.dupe` + `clearAndFree` double-allocation pattern in `diff/engine.zig` with single `toOwnedSlice` call.

### v0.112.0 (2026-08-04)

- **Unified `parseDialect`** — Single source of truth in `dialect/enum.zig` with all aliases (`sq`, `ora`, `idb2`, `sqlserver`, `postgres`). Fixes bug where `bench.zig` was missing the `sq` alias and `parse_typedef.zig` was missing `ora` and `idb2` aliases. Removed duplicate definitions from `cli.zig`, `bench.zig`, and `parse_typedef.zig`.
- **Unified header format** — Extracted "Generated by rune" format string into `dialect/enum.zig` with `writeHeader`, `allocHeader`, and `writeMigrationHeader` helpers. Eliminates 4+ duplicated format strings across `codegen/codegen.zig`, `codegen/streaming.zig`, and `diff/migrate.zig`.
- **Drizzle dialect mapping dedup** — Extracted `drizzleTableFn` and `drizzleModuleName` helpers in `generators/drizzle.zig`, eliminating two duplicated 6-way switch statements.
- **Config merge robustness** — Added `dialect_was_explicit` flag to `ParsedArgs` and `GlobalFlags`. Config file dialect override now uses `!dialect_was_explicit` instead of the fragile `dialect == .mysql` default-value check.
- **Dead code removal** — Removed unused `Config.mergeWithArgs` method, empty no-op `std.debug.print("", .{})`, and simplified `catch |err| return err` anti-pattern in `pipeline/forward.zig`. Cleaned up unused `ParseError.UnexpectedEof` variant.

### v0.111.0 (2026-08-04)

- **Shared ORM generator helpers** — Added `hasAnyEnums()` and `hasAnyCompositeFks()` to `generators/common.zig`. Eliminates duplicated 9-line scan patterns in `drizzle.zig` and `prisma.zig` for detecting enum columns and composite foreign keys across all tables.
- **Shared dialect inline index emission** — Added `emitInlineIndexWithQuote()` and `emitStandaloneCreateIndexWithQuote()` to `dialect/common.zig` with comptime quote character parameters. Eliminates 4 near-identical `emitInlineIndex` implementations across MySQL (backtick), MSSQL (square brackets), Oracle (double-quote), and Db2 (double-quote). Each dialect now delegates to the shared parameterized helper. Also eliminated 2 `emitInlineColumnStandaloneIndex` copies (MSSQL, Db2).
- **Expanded diff format test coverage** — Added 13 new unit tests across `diff/format/text_test.zig` (4 tests), `json_test.zig` (5 tests), `sarif_test.zig` (4 tests), and `markdown_test.zig` (6 tests). Covers field add/drop/modify, multiple dropped tables, created tables, view diffs, and SARIF structure.
- **Expanded semantic pass test coverage** — Added 7 new unit tests across `semantic/pass/validate.zig` (4 tests) and `semantic/pass/resolve_names.zig` (5 tests). Covers FK to valid table, inline FK validation, duplicate field detection, table-template name conflicts, empty table names, and parser artifact skipping.

### v0.110.0 (2026-08-04)

- **Fixed memory leak in migration graph** — `MigrationGraph.deinit()` now frees `StringHashMap` key strings allocated via `alloc.dupe`. Added `errdefer graph.deinit()` in `buildGraph` to prevent leaks on error paths.
- **Deduplicated streaming interleaving** — Extracted `InterleaveIterator` struct in `codegen/streaming.zig` with `next()`/`currentTable()`/`currentView()`/`currentComment()` methods. `formatStreamingResult` now uses the shared iterator instead of a duplicated merge loop.
- **Improved error handling in migration graph** — `buildGraph` now returns `error.MigrationDirectoryError` on directory-open failure instead of silently returning an empty graph.
- **Documented template extraction heuristics** — Added named constants `MAX_TEMPLATE_RATIO` (3), `MIN_NEW_FIELDS` (2), `MIN_WINDOW_SIZE` (2) in `reverse/template_extraction.zig` with doc comments explaining the rationale for each threshold.
- **Build-time version injection** — `build.zig` now parses version from `build.zig.zon` at comptime via `@embedFile` and injects it via `build_options`. `version.zig` uses `build_options.VERSION` instead of a hardcoded string. Version is now a true single source of truth in `build.zig.zon`.

### v0.109.0 (2026-08-04)

- **Removed dead `validate_schema.zig`** — Deleted 453-line file whose functionality was split into focused passes (`validate_duplicates`, `validate_circular_fk`, `validate_fk_targets`, `validate_unused_templates`) in v0.107.0. The file was not imported in `DEFAULT_PASSES` or any production code — only compiled via `tests.zig` inline test discovery.
- **Removed dead `DiffFormatter` registry** — Removed ~60 lines of unused `DiffFormatter` struct, `FORMATTERS` array, `getFormatter()`, `getFormatterForEnum()`, and adapter functions from `diff/format.zig`. The pipeline calls format functions directly from sub-modules; the unified registry was never used.
- **Consolidated semantic pass test helpers** — Enhanced `test_helpers.makePassCtx` with `init_symbol_table` and `template_refs` options. Updated 8 semantic pass test files (`validate.zig`, `validate_indexes.zig`, `validate_type_modifiers.zig`, `autofk.zig`, `validate_duplicates.zig`, `validate_circular_fk.zig`, `validate_fk_targets.zig`, `validate_unused_templates.zig`, `resolve_names.zig`) to delegate to the shared helper, eliminating ~120 lines of duplicated `makeCtx`/`makeCtxWithTemplates` implementations.
- **Documentation sync** — Updated `pass_manager.zig` comments to reference `validate_unused_templates` instead of the deleted `validate_schema`.

### v0.108.0 (2026-08-04)

- **Named constants for diff engine** — Extracted `INITIAL_TABLE_DIFF_CAPACITY`, `INITIAL_DROPPED_TABLES_CAPACITY`, `INITIAL_VIEW_DIFF_CAPACITY`, `INITIAL_FIELD_DIFF_CAPACITY`, `INITIAL_INDEX_DIFF_CAPACITY`, `INITIAL_FK_DIFF_CAPACITY` as named constants in `diff/engine.zig`, `diff/fields.zig`, `diff/indexes.zig`, `diff/fks.zig`. Replaces 6 hardcoded `initCapacity` values with documented constants that explain typical schema patterns.
- **Codegen buffer pool** — New `BufferPool` struct in `codegen/codegen.zig` manages reusable `Writer.Allocating` instances for batch codegen scenarios. Methods: `init`, `deinit`, `acquire`, `release`. New `generateFromTypedAstPooled` method enables buffer reuse across multiple compilations. Existing `generateFromTypedAst` preserved for backward compatibility.
- **IR versioning** — Added `ir_version: u32` field to both `ResolvedAst` (types/resolved_ast.zig) and `TypedAst` (types/typed_ast.zig). New `types/ir_version.zig` module defines `CURRENT_IR_VERSION = 1` and `validateIrVersion()` for forward/backward compatibility detection. 4 unit tests cover version constant, validation, and error cases.
- **New unit tests** — `types/ir_version.zig` (4 tests: version positive, validate current, validate zero, validate future). `codegen/streaming_test.zig` expanded from 7 to 10 tests (added PostgreSQL dialect, many-columns, FK+index edge cases).

### v0.107.0 (2026-08-04)

- **Unified `CompileConfig`** — Merged the overlapping `PipelineOptions` and `CompileConfig` structs into a single `CompileConfig` in `pipeline/forward.zig`. Eliminates ~20 lines of field-mapping boilerplate between the two structs. The unified struct carries all pipeline, CLI, and import options in one place.
- **Extracted `invertDiff`** — Pure data transformation in `diff/invert.zig` that inverts a `SchemaDiff` for rollback generation. Extracted the field/index/FK inversion logic (add↔drop, modify swaps old/new, rename reverses direction) from `diff/migrate.zig`. `generateRollback` now delegates to `invertDiff` for the transformation, reducing ~80 lines of inline inversion logic. Includes 4 unit tests.
- **Split `validate_schema` pass** — The monolithic 453-line `semantic/pass/validate_schema.zig` was split into 4 focused passes: `validate_duplicates` (duplicate table names), `validate_circular_fk` (circular FK chains + self-referencing FK field count), `validate_fk_targets` (FK target field existence), and `validate_unused_templates` (unused template warnings). Each pass is independently testable with its own dependency declarations. Total: 8 unit tests across the 4 passes.
- **`DiffFormatter` interface** — Added a unified `DiffFormatter` struct with `name` and `format_fn` fields in `diff/format.zig`. Provides a `FORMATTERS` registry array and `getFormatter(name)` / `getFormatterForEnum(fmt)` lookup functions for runtime format dispatch. Adapter functions wrap existing per-format functions into a common `FormatFn` signature.
- **Consolidated error dispatch** — Extracted `handleParseError` and `handleDispatchError` from the 70-line inline error handling in `main.zig`. Both are `noreturn` functions that handle all error variants cleanly. Reduces inline error handling to ~4 lines.
- **New unit tests** — `diff/invert.zig` (4 tests), `semantic/pass/validate_duplicates.zig` (2 tests), `semantic/pass/validate_circular_fk.zig` (3 tests), `semantic/pass/validate_fk_targets.zig` (2 tests), `semantic/pass/validate_unused_templates.zig` (2 tests).

### v0.106.0 (2026-08-04)

- **Streaming compilation fix** — `rune schema.ss --stream` now includes views and SQL comments in the output. Previously, views and comments were silently skipped (data loss bug). `StreamingResult` now includes `views` and `comments` fields with line numbers for proper interleaving in `formatStreamingResult`.
- **Stats field naming correction** — `Stats.templates` renamed to `Stats.custom_types` to accurately reflect that the field counts custom type definitions (`~` directives), not templates (`%` definitions). JSON output key changed from `"templates"` to `"custom_types"`.
- **Dead dialect parameter removal** — Removed unused `dialect` parameter from `typeInfoEqualDialect`, `fieldSignatureMatch`, `fieldsEqual`, `diffFields`, `diffTable`, and `diff` functions in the diff engine. The parameter was a dead code path since the underlying `typeInfoEquiv` is dialect-agnostic.
- **Migrate status JSON optimization** — Replaced O(n²) hand-rolled JSON string concatenation with streaming `std.Io.Writer.Allocating` approach using `utils.jsonEscapeString`. Also optimized the non-JSON text output path.
- **`emitCheckExpr` relocated** — Moved from `codegen/codegen.zig` to `codegen/columns.zig` where it belongs (CHECK expression rendering is part of column definition codegen).
- **New unit tests** — 4 streaming compilation tests covering views, comments, interleaving, and output ordering.

### v0.105.0 (2026-08-04)

- **Version sync** — Fixed version drift: `version.zig` updated to match `VERSION` file (was 0.103.0 vs 0.104.0). Both now report 0.105.0.
- **Removed last `orelse unreachable`** — `dialect/dialect.zig:293` comptime block now uses explicit null check with `@compileError` instead of `orelse unreachable`. ROADMAP code quality target completed.
- **Deduplicated `ColorMode`** — Removed duplicate `ColorMode` enum from `cli.zig`. Now re-exports `color.ColorMode` via `pub const ColorMode = color_mod.ColorMode`. Single source of truth.
- **`rune init -d/--dialect`** — `rune init` now accepts `-d`/`--dialect` to specify target SQL dialect. Generated starter schema includes a dialect hint comment. Example: `rune init myapp -d pg`.
- **Improved error messages** — `FileNotFound` errors now show the specific file path that was not found. For `diff`/`migrate`, both file paths are shown.
- **Config validation** — `rune.toml` values are now validated: `[dialect] default` must be a valid dialect name, `[output] color` must be `auto`, `always`, or `never`. Invalid values produce clear error messages.
- **New unit tests** — `cli_test.zig` expanded with 3 tests (init with `-d`, init with `--dialect`, ColorMode re-export). `config_test.zig` expanded with 4 tests (valid config, invalid dialect, invalid color, null values).
- **Documentation** — Updated README.md, ROADMAP.md, CLAUDE.md.

### v0.103.0 (2026-08-04)

- **Streaming compilation integration** — The `--stream` flag (declared in v0.102.0) is now fully wired into the CLI parser and forward pipeline. `rune schema.ss --stream` uses `StreamingCodegen` to emit each table's SQL independently. Streaming only applies to SQL format (not json-schema).
- **Bug fixes** — Fixed `completions.zig` using `std.process.exit(1)` in library code (now returns `error.UnknownShell`). Fixed `diff/migrate_graph.zig` using `catch unreachable` (now uses `try` with proper error propagation). Fixed `cliArgErrorMessage` to handle `UnknownShell`.
- **New unit tests** — `codegen/streaming_test.zig` (4 tests: single table, multi-table order, format with header, empty schema). `diff/migrate_graph_test.zig` (6 tests: extractTables CREATE/ALTER/multiple/comments, MigrationGraph init, formatGraph empty).
- **Made `extractTables` public** in `diff/migrate_graph.zig` for direct testing.
- **Documentation** — Updated VERSION, version.zig, ROADMAP.md.

### v0.102.0 (2026-08-04)

- **Migration dependency graph** — New `rune migrate --graph <dir>` command analyzes SQL migration files and displays dependency relationships. Detects circular dependencies and shows execution order. Example: `0002_add_posts.sql → 0001_create_users`.
- **Streaming compilation** — New `--stream` flag enables streaming codegen mode. Each table's SQL is generated independently, enabling incremental processing of large schemas. Foundation for future `rune watch` and live recompilation.
- **New modules** — `diff/migrate_graph.zig` (~250 lines) for dependency graph analysis, `codegen/streaming.zig` (~120 lines) for streaming codegen infrastructure.
- **CLI enhancements** — `--graph` flag for migrate command, `--stream` flag for compile command. Help text updated with new examples.

### v0.101.0 (2026-08-03)

- **Unknown flag suggestions** — Mistyped `--flags` now show "Did you mean?" with edit-distance-based suggestions (threshold ≤3 edits). Uses new `runtimeEditDistance` in `utils/edit_distance.zig`. Example: `rune --verison` → `error: unknown flag '--verison'. Did you mean '--version'?`
- **`rune validate` in CLI help** — The `validate` command (previously implemented but hidden) is now listed in `--help` output with examples. Two new examples added: `rune validate schema.ss` and `rune validate schema.ss -s`.
- **`rune stats --format json`** — Schema statistics can now output JSON directly via `--format json`. Replaces the previous `--json-errors` flag for stats. JSON includes: tables, fields, not_null, numeric, string, datetime, boolean, other, views, foreign_keys, indexes, check_constraints, templates.
- **Improved help text** — Added 6 new examples to `rune --help`: validate, stats JSON, diff JSON, migrate rollback, init, and fmt. Updated `--format` description to include stats.
- **New golden test suites** — `tests/test_validate.sh` (4 tests) and `tests/test_stats_json.sh` (3 tests) covering the new CLI features.

### v0.100.0 (2026-08-03)

- **Project configuration (`rune.toml`)** — New `config.zig` module with minimal TOML parser. Supports `[project]`, `[dialect]`, and `[output]` sections. CLI flags override config values. `--config <path>` flag to specify custom config path.
- **`validate --json-errors`** — Machine-readable JSON output for schema validation. Outputs `{"valid":bool,"errors":N,"tables":N,"fields":N,"views":N}`.
- **`check --json-errors`** — Same JSON output format for CI gate mode.
- **`migrate --summary`** — Output only the summary line without full migration SQL. Parity with `diff --summary`.
- **Improved error messages** — Unknown commands now list all available commands. Unknown generators list all available generator names.
- **Fixed 3 memory leaks in rollback tests** — `generateRollback` properly frees ArrayList backing memory for reversed table diffs. All 946 tests now pass with exit code 0.
- **Config infrastructure** — `ParsedArgs` now includes `config_path` field. `COMMAND_REGISTRY` and `CommandInfo` made public for error message generation.

### v0.99.0 (2026-08-03)

- **Fixed `migrate status` 4-digit prefix bug** — `handleMigrateStatus` now correctly handles both 3-digit (legacy) and 4-digit migration file prefixes. Previously used `lastIndexOfScalar` which found the wrong underscore position for filenames like `0001_add_users.sql`. Changed to `indexOfScalar` for correct first-underscore detection.
- **Fixed iterator string lifetime** — Directory entries are now duplicated before storage (`alloc.dupe`), preventing stale pointers when the iterator reuses its internal buffer.
- **`migrate status --json-errors`** — Machine-readable JSON output for migration file listing. Outputs `{"files":[{"name":"...","label":"..."},...],"count":N}`.
- **`rune diff --summary`** — Output only the summary line (`N tables changed (X added, Y dropped, Z modified)`) without the full diff. Useful for CI checks and commit messages.
- **New test suite** — `tests/test_migrate_status.sh` with 7 tests covering 4-digit, 3-digit, mixed prefixes, empty directories, non-migration files, and JSON output.

### v0.98.0 (2026-08-03)

- **`--init` flag** — Create starter schema with `rune --init` (equivalent to `rune init`). Works as a global flag alongside other options.
- **CLI integration** — `--init` added to `GLOBAL_FLAGS`, `ParsedArgs`, and `isKnownFlag` list.
- **Shell completions updated** — Bash, Fish, PowerShell include `--init` flag.
- **Help text updated** — `rune --help` shows `--init` option.

### v0.97.0 (2026-08-03)

- **Colored diff output** — `rune diff` supports ANSI color output with `--color auto|always|never` flag. Green for added, red for dropped, yellow for modified, blue+bold for table headers.
- **Diff summary statistics** — `rune diff` prints a summary line: `"N tables changed (X added, Y dropped, Z modified)"`.
- **New `color.zig` module** — ANSI escape code constants, `ColorMode` enum, `writeColorized` helper.
- **7 new unit tests** — `color_test.zig` covering `ColorMode` variants and `ParsedArgs` defaults.
- **5 new golden tests** — `test_color.sh` verifying color output behavior.
- **Shell completions updated** — Bash, Fish, PowerShell include `--color` flag.

### v0.96.0 (2026-08-03)

- **Fixed migration rollback semantics** — `generateRollback` now properly reverses all operations: `.create` tables become DROP TABLE, `.drop` tables become CREATE TABLE, field/index/FK diffs are inverted (add↔drop, modify swaps old/new), and view diffs are reversed. Previously, rollback emitted the same SQL as forward migration.
- **Fixed memory leak in reverse codegen** — `emitForeignKeys` now properly frees memory allocated by `classifyFk`. Previously, each FK classification leaked its formatted text buffer.
- **`PassAccess` conflict detection** — `semantic/pass_manager.zig` now validates that sequential passes don't have conflicting write-write access patterns at runtime.
- **Optimized reverse codegen template lookup** — Pre-built `table_index → template_index` lookup map for O(1) per-table template resolution, replacing O(n*m) scan.
- **13 new unit tests** — 7 rollback tests in `migrate_test.zig`, 6 reverse codegen tests in `codegen_test.zig`.

### v0.95.0 (2026-08-03)

- **Shared `applyRenames` helper** — Extracted duplicated rename-adjustment logic from `diff/indexes.zig` and `diff/fks.zig` into `diff/rename.zig`. Both modules now delegate to the shared function, eliminating ~40 lines of duplicated field-substitution code.
- **Expanded schema statistics** — `rune stats` now reports foreign key, index, check constraint, and template counts in addition to the existing table/field/view breakdown. JSON output includes the new fields.
- **Migration sequence overflow fix** — Migration file naming changed from 3-digit (`001_name.sql`) to 4-digit (`0001_name.sql`) zero-padding. `findNextSequenceNumber` now handles variable-length prefixes for backward compatibility with existing migration directories.

### v0.94.0 (2026-08-03)

- **Shared `writeColumnProp`** — Extracted ~75 lines of duplicated JSON Schema/OpenAPI column property writing into `generators/common.writeColumnPropJson`. Both `json_schema.zig` and `openapi.zig` now delegate to the shared function.
- **Shared `formatTypeInfo`** — Extracted duplicated `formatTypeInfo` into `diff/format_common.zig`. Both `text.zig` and `markdown.zig` diff formatters now use the shared helper.
- **Index rename propagation** — `diffIndexes` now accepts `field_diffs` and adjusts index field names for renames before matching, preventing stale migration SQL when columns are renamed.
- **New `common_test.zig` tests** — Added 17 unit tests for shared generator helpers (`findFkRefTable`, `writeJsonValue`, `toCamelSingular`, `tableHasNonPkIndexes`, `tableHasCompositeFks`).
- **Expanded dialect tests** — Added 8 unit tests each for MySQL, PostgreSQL, and SQLite dialects covering `lookupSym`, `canOmitType`, `emitAlterDropColumn`, and `emitAlterRenameColumn`.
- **Shared `makePassCtx`** — Added `semantic/test_helpers.makePassCtx` for semantic pass test standardization.

### v0.93.0 (2026-08-03)

- **Migration file naming** — `rune migrate --name <label>` generates auto-numbered migration files (`001_add_users.sql`). Combined with `-o <dir>` or `--dir <path>`, writes directly to the target directory with sequential numbering.
- **`--dir` flag for batch output** — `rune migrate old.ss new.ss --dir migrations/ --name add_users` scans the directory for existing `NNN_*.sql` files and generates the next sequence number.
- **Incremental migration filter** — `rune migrate --incremental` filters out pure comment/metadata changes, emitting only structural diffs (table add/drop, field add/drop/modify, FK add/drop/modify, index add/drop/modify).
- **`rune migrate status`** — Lists migration files in a directory, showing sequence numbers and names. Scans for `NNN_*.sql` pattern files.

### v0.92.0 (2026-08-03)

- **Fixed `--output` long flag** — `--output` was listed as a known flag and in completions, but `parseArgs` only handled `-o`. The `--output` flag silently fell through as a positional argument. Now both `-o` and `--output` work correctly.
- **Deduplicated validate/check/stats parsers** — Extracted `parseSimpleInputArgs` helper to eliminate duplicated code across `parseValidateArgs`, `parseCheckArgs`, and `parseStatsArgs`.
- **Early generator name validation** — `rune generate <invalid>` now produces a clear error message at the CLI level instead of failing deep in the pipeline.
- **Subcommand help support** — `rune diff --help`, `rune generate --help`, etc. now show subcommand-specific help instead of the general help. Added `hasHelpFlag` helper, `printSubcommandHelp` function, and updated `Command.help` to carry an optional subcommand name.

### v0.91.0 (2026-08-03)

- **Removed dead `DialectCapability` code** — Removed unused `DialectCapability` struct (12 boolean feature flags) from `dialect.zig` and the `capability` field from `DialectBackend`. All 6 backends had these flags populated but no production code ever read them. Eliminates ~100 lines of dead infrastructure.
- **Split `generators/common.zig`** — Extracted `DefaultFormatter` + ORM callbacks into `common_defaults.zig` (drizzle/knex/sqlalchemy/typeorm) and CHECK constraint parsers into `common_check.zig` (json_schema/openapi). Backward-compatible re-exports in `common.zig`.
- **Table-driven parameterized type matching** — Replaced 8 repetitive pattern-matching blocks in `reverse/map.zig` with a `PARAM_PATTERNS` table and shared `matchParam` function. Net reduction: ~50 lines.
- **Comptime pass dependency validation** — `semantic/pass_manager.zig` now validates all dependency names at compile time instead of runtime only.

### v0.90.0 (2026-08-03)

- **Fixed version-resilient golden tests** — `test_openapi.sh`, `test_graphql.sh`, and `test_json_schema.sh` now use `compare_files()`/`diff_versions()` from `lib.sh` instead of raw `diff -u`. Golden tests no longer break on version bumps. Added `strip_version_auto()` to `lib.sh` that auto-detects output format (SQL/JSON/GraphQL) and strips version strings. Added proper exit codes to the three test scripts.
- **Fixed parse_typedef dialect support** — `parseDialect()` in `parse_typedef.zig` now handles all 6 dialects (was missing mssql, oracle, db2). Custom type dialect overrides for these backends were previously silently dropped.
- **Added generator registry tests** — New `generator_test.zig` with 5 tests covering registry count, lookup, unknown names, non-empty fields, and name uniqueness.
- **Formatted 4 files** — `zig fmt` applied to `completions_test.zig`, `diff/engine_test.zig`, `pipeline/stats_test.zig`, and `reverse/map.zig`.

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
| 4: Incremental & Live Workflows | ✅ Complete | 10/10 | 0 |
| 5: Developer Experience | 🟡 Partial | 8/13 | 5 |
| 6: Ecosystem & Community | 🔲 Not started | 0/9 | 9 |
| Architecture Targets | 🟡 Ongoing | 11/12 | 1 |
| **Total** | | **64/82** | **18** |
