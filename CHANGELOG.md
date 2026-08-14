# Changelog

All notable changes to this project will be documented in this file.

## [0.282.0] - 2026-08-14

### Added
- **Pydantic v2 generator** — `rune generate pydantic` emits Pydantic v2 `BaseModel` classes from `.ss` schemas (dialect-agnostic, `generators/pydantic.zig`). Registers via the pluggable `REGISTRY` — an end-to-end exercise of the open-closed generator architecture.
- **Registry collision guard** — comptime architecture-health test asserts no two `REGISTRY` entries share a `name`.

### Changed
- **Documentation sync** — Added `pydantic` to generator lists in CLAUDE.md, ARCHITECTURE.md, and both README files; bumped unit-test count (1,929+ → 1,933+); synchronized version strings 0.281.0 → 0.282.0 across `VERSION`, `rune/build.zig.zon`, `rune/VERSION`, and packaging manifests (npm, scoop, homebrew, vscode).

## [0.268.0] - 2026-08-12

### Added
- **CLI hooks tests** — Added unit tests for `cli/hooks.zig` (handleHooks, HOOK_PRECOMMIT constant validation).

### Changed
- **Documentation sync** — Updated test file counts across documentation (117 → 118 colocated test files, 1868+ → 1876+ unit tests) in CLAUDE.md, ARCHITECTURE.md.

## [0.266.0] - 2026-08-12

### Fixed
- **Double-lint in validation** — `rune validate --strict --fix` no longer runs `lintSchema` twice. Lint results are now cached and shared between strict check and fix application.
- **`std.process.exit` in library code** — `pipeline/generate.zig` now returns `error.GeneratorHealthCheckFailed` instead of calling `std.process.exit(1)`, improving testability.

### Changed
- **Shared compile helper** — Extracted duplicate `compileToTypedAst` function from `pipeline/generate.zig` and `pipeline/handlers.zig` into `pipeline/compile_helper.zig` (DRY fix, net -11 lines across 4 files).
- **Dead code removal** — Removed unused private methods `formatAlloc` and `writeMajorMinor` from `version.zig` (never called from production code).
- **Free functions** — Converted `emitSchemaHeader` and `emitStandaloneIndexes` in `reverse/codegen.zig` from struct methods to free functions (removed unused `self` parameters).
- **Formatting** — Fixed zig fmt violations in 5 files (`cli/types.zig`, `formatter.zig`, `lint/handlers/portability.zig`, `lsp/code_actions.zig`, `semantic/pass_manager.zig`).

## [0.253.0] - 2026-08-11

### Fixed
- **VERSION file inconsistency** — VERSION file was stale at 0.251.0 while build.zig.zon was 0.252.0. Now both are synchronized.

### Changed
- **Dead code cleanup** — Removed pub visibility from 11 functions across 6 modules that had zero external references: `mmapFile` (io.zig), `parseConfig`/`warnUnknownKeys` (config.zig), `generateFromSchema`/`generateFromSchemaBatch`/`compileToTypedAst` (handlers.zig), `initVerbose` (analyzer.zig), `printDiagnosticColor` (diagnostic.zig), `validateIrVersion` (ir_version.zig), `formatAlloc`/`writeMajorMinor` (version.zig).
- **Dialect import consistency** — Pipeline modules (diff.zig, migrate.zig, handlers.zig, forward.zig, reverse.zig) now import `Dialect` from `dialect/enum.zig` instead of through `codegen/codegen.zig`. Reduces unnecessary coupling between pipeline and codegen layers.
- **Packaging versions** — Updated npm and VS Code extension manifests from 0.243.0 to 0.253.0.

## [0.246.0] - 2026-08-11

### Added
- **`go_to_definition` tests** — Added 5 unit tests for LSP go-to-definition: FK reference navigation, FK column navigation, non-FK column returns null, table name line returns null, FK in same table navigation.
- **Format check UX** — `rune format --check` now prints "formatting needed" message when file requires formatting. `rune format --diff` now shows "N line(s) would change" summary after displaying differences.

### Changed
- **Test count** — 108 colocated test files, 1,785+ unit tests (up from 107 / 1,780+).
- **Documentation** — Updated CLAUDE.md and README.md with current test metrics.

## [0.229.0] - 2026-08-11

### Added
- **`column-boolean-naming` lint rule** — Warns when boolean columns don't use `is_`/`has_`/`can_` prefix convention. Improves schema readability and consistency.
- **`fk-depth` lint rule** — Warns when foreign key reference chain exceeds 3 levels. Helps catch overly complex FK hierarchies that may impact performance.

### Changed
- **Lint handler refactoring** — Split `lint/handlers/validation.zig` (586 lines) into 4 focused modules: `fk.zig` (5 FK rules), `index.zig` (3 index rules), `view.zig` (3 view rules), `enum.zig` (4 enum rules). `validation.zig` now contains only general validation rules (5 rules) plus shared helpers.
- **Lint rule count** — Expanded from 37 to 39 rules.
- **Handler module count** — Expanded from 4 to 8 modules.

## [0.228.0] - 2026-08-11

### Added
- **`view-select-star` lint rule** — Warns when views use SELECT * instead of explicit column lists. Helps catch portability and schema evolution issues early.
- **`enum-value-duplicate` lint rule** — Warns when a custom type has duplicate enum values. Helps catch copy-paste errors in type definitions.

### Changed
- **Lint rule count** — Expanded from 35 to 37 rules.

## [0.224.0] - 2026-08-11

### Changed
- **Data-driven help system** — Replaced 200-line if-else chain in `printSubcommandHelp` with data-driven `COMMAND_HELP` registry (17 commands). Help is now indexed the same way as CLI dispatch and lint rules.
- **Removed duplicate `DocsFormat` enum** — Consolidated to single definition in `cli/types.zig`, re-exported from `pipeline/handlers.zig`.

### Fixed
- **Help text accuracy** — Lint help claimed "30 rules" (actual: 33) and "8 fixable rules" (actual: 9). Both corrected.
- **Orphaned `-T` flag in global help** — Removed from global options (already documented in reverse subcommand help).
- **Missing command help sections** — Added detailed help for export, docs, stats, version, migrate_status, and help commands.

## [0.218.0] - 2026-08-10

### Changed
- **Pipeline decomposition** — Extracted migrate handler from `pipeline/diff.zig` into `pipeline/migrate.zig`. `diff.zig` now contains only `DiffConfig`, `handleDiff`, `prepareDiff`, `prepareDiffFromSql`, `emitTraceAndStats` (~163 lines). `migrate.zig` contains `MigrateConfig`, `handleMigrate`, `handleMigrateStatus`, `filterIncrementalChanges`, `collectMigrateFiles`, `findNextSequenceNumber`, `formatMigrationFileName` (~306 lines). Single-responsibility: diff owns diff computation and display; migrate owns migration SQL generation and file management.
- **`tune.zig` allocator fix** — Replaced hardcoded `std.heap.page_allocator` in `findBestFieldSet` with the passed-in allocator parameter, consistent with project conventions. All 10 `page_allocator` references replaced.

### Fixed
- **`tune.zig` documentation** — Added descriptive comments to `handleTune` branches explaining dry_run vs normal mode behavior.

## [0.213.0] - 2026-08-10

### Added
- **WASM API: `rune_format`** — New export that auto-formats .ss schema text with consistent style (indentation, blank lines, trailing whitespace).
- **WASM API: `rune_tune`** — New export that auto-extracts common fields into template definitions.
- **WASM API: `rune_generate`** — New export that runs pluggable generators (prisma, drizzle, openapi, etc.) via WASM. Options: `generator=<name> dialect=<dialect>`.
- **CLI: `rune version --json`** — Machine-readable JSON output for version information.
- **WASM test coverage** — Added 11 new unit tests for `rune_format`, `rune_tune`, `rune_generate` (including error cases).

## [0.210.0] - 2026-08-10

### Added
- **WASM API: `rune_stats`** — New export that compiles a schema and returns statistics as JSON (tables, fields, types, constraints).
- **WASM API: `rune_validate`** — New export that validates a schema and returns results as JSON (valid/error status, table/field counts).
- **WASM API: `rune_last_error_code`** — Numeric error codes (0=success, 1=syntax, 2=type, 3=FK, 4=semantic, 5=unknown) for programmatic error handling.
- **WASM test coverage** — Added 15+ new unit tests for `rune_migrate`, `rune_reverse`, `rune_stats`, `rune_validate`, option parsing, and error codes.

### Fixed
- **Parser memory leak** — Removed unnecessary `deinit` call in `stripEngineTokens` (`parse_table.zig`) that confused the debug allocator. The arena allocator handles cleanup.
- **WASM test syntax** — Updated test schemas from old syntax (`id n pk`) to current syntax (`id N ++`).
- **WASM option length** — Fixed incorrect string length parameters in `rune_diff` format tests (json/sarif/markdown).

### Changed
- **WASM API refactoring** — Extracted `parseDialectOption` and `parseDiffFormatOption` helpers to deduplicate dialect/format parsing across export functions. Updated `rune_diff` to use new format modules (`text_fmt`, `json_fmt`, `sarif_fmt`, `markdown_fmt`). Updated `rune_migrate` to include TypeResolver for proper type resolution. Updated `rune_reverse` to use `ReverseCodegen.init().generate()` API.

## [0.209.0] - 2026-08-10

### Fixed
- **Parser memory leak** — Fixed `BlockState.reset()` in `parser.zig` that allocated a new `parents_buf` (4 elements) on each call without reusing existing capacity. Changed to use a fixed-size `[4][]const u8` array, eliminating unnecessary allocations. Also fixed `parseTemplateHeader` in `parse_template.zig` to properly free the temporary `parents_buf` allocation after copying parent names.

### Changed
- **Unified config warnings** — Replaced direct `std.debug.print` calls in `config.zig` with `fmt.printWarn` from `diagnostic/format.zig` for consistent error output format.

## [0.208.0] - 2026-08-10

### Changed
- **Lint rules refactoring** — Split `lint/rules.zig` (1,052 lines) into 4 category-based handler modules: `lint/handlers/structural.zig` (7 rules), `lint/handlers/naming.zig` (6 rules), `lint/handlers/validation.zig` (14 rules), `lint/handlers/compat.zig` (3 rules). `lint/rules.zig` retains dispatch table, `RuleInfo`, `RULE_INFO`, and helper functions (~130 lines).
- **Build system cleanup** — Removed unused `run_golden` artifact from `build.zig` that was never wired into any step.

## [0.207.0] - 2026-08-10

### Fixed
- **Critical template inheritance bug** — Fixed arena allocator memory corruption caused by `BlockState.reset()` and `BlockState.deinit()` freeing `parents_buf` via `alloc.free()` while previously flushed templates still referenced it through `Template.parents` slices. All 5 template inheritance golden tests now pass (11-template-inherit, 12-template-deep, 13-template-extends, 51-inherit-override, 66-template-mixins).

## [0.206.0] - 2026-08-10

### Added
- **Test coverage expansion** — Added unit tests for `dialect/enum.zig` (parseDialect, alias resolution, writeHeader), `utils.zig` (optionalStrEq, jsonEscapeString), `cli/types.zig` (Command enum, ParsedArgs defaults, COMMAND_REGISTRY, GlobalFlags). 20 new unit tests (1,548 total).

### Changed
- **Documentation accuracy** — Fixed stale documentation metrics across CLAUDE.md, README.md, ARCHITECTURE.md (test file count 93→100, test count 1,438+→1,548+).

## [0.205.0] - 2026-08-10

### Added
- **`textDocument/foldingRange` LSP support** — Code folding for `.ss` files. Detects foldable regions for table blocks (`# name { ... }`), template blocks (`% name ...`), and `@if`/`@endif` conditional blocks. New `lsp/folding_range.zig` module with 5 unit tests.
- **`textDocument/typeDefinition` LSP support** — Navigate from a field's custom type to its `~` definition. Matches columns with enum values against custom type definitions. New `lsp/type_definition.zig` module with 2 unit tests.
- **LSP capabilities** — Added `foldingRangeProvider` and `typeDefinitionProvider` to server capabilities. Updated dispatch table with 2 new handlers.
- **2 new unit tests** for LSP features (1522+ total)

### Changed
- **Documentation accuracy** — Fixed CHANGELOG.md gap (added v0.195-v0.204 entries). Fixed ROADMAP.md Phase 6 description ("Not started" → "In progress — 3/8 items done"), Phase 7 count (9/10 → 8/10), Architecture Targets (15/15 → 19/22), and total (97/105 → 100/117).

## [0.204.0] - 2026-08-10

### Fixed
- **Plan inversion `type_def = undefined`** — Fixed `diff/plan.zig` `invertPlan()` that set `type_def` to `undefined` when inverting `drop_type` to `create_type`. Rollback SQL for custom type drops now correctly preserves the type definition.
- **`emitEnumValues` placeholder** — Implemented proper enum value extraction from `CustomType` definition in `diff/migrate.zig`. Was emitting hardcoded `'-- values --'` placeholder instead of actual enum values.
- **MSSQL `sp_rename` missing table qualifier** — Fixed `dialect/mssql.zig` `emitAlterRenameColumn` to include table name prefix in `sp_rename` call (e.g., `sp_rename 'table.column', 'new_column'`).

### Changed
- **Improved lint config error reporting** — Invalid numeric thresholds in `.rune-lint.toml` now return errors instead of silently ignoring them.
- **Removed `std.process.exit` from library code** — Extracted `cli/lint_cmd.zig` to return error codes instead of calling `process.exit`, improving testability. Added `StrictWarnings` error type for lint strict mode.

### Added
- **3 new unit tests** for plan inversion (1520+ total)

## [0.203.0] - 2026-08-10

### Added
- **Custom type migration support** — Added CREATE/DROP TYPE SQL generation for PostgreSQL dialect in migration output. MySQL emits comments for unsupported dialects.
- **FK field count validation** — Warns when foreign key fields count doesn't match referenced fields count.
- **8 new semantic pass tests** — 4 tests for `resolve_conditionals`, 4 tests for `validate_views`.

### Changed
- **Deduplicated ORM FK detection loops** — Knex and SQLAlchemy generators now use shared `common.findFkRefTable` helper instead of duplicate loops.

## [0.202.0] - 2026-08-10

### Added
- **`LintRule.description()` method** — Single source of truth for rule descriptions (30 rules).
- **`RuleInfo` struct and `RULE_INFO` constant** — Derived from `LintRule` enum, eliminates hardcoded lists in `lint_cmd.zig`.
- **4 new unit tests** for `RULE_INFO` consistency (1502 total).

### Changed
- **Refactored `showAllRules` and `initLintConfig`** — Now iterate `RULE_INFO` instead of maintaining separate hardcoded lists.

## [0.201.0] - 2026-08-10

### Added
- **`--show-rules` flag** — Lists all 30 lint rules with descriptions and fixability status.
- **`--init` flag** — Generates starter `.rune-lint.toml` config file with all rules.
- **`cross-dialect-types` lint rule** — Warns about MySQL-specific types (UNSIGNED, TINYINT, MEDIUMTEXT) that don't port to other dialects.
- **4 new unit tests** (1498 total).

### Changed
- **Enhanced lint summary** — Shows fixable count alongside error/warning counts.

## [0.200.0] - 2026-08-10

### Fixed
- **ARCHITECTURE.md stale pass list** — Added `template_type_conflict`, fixed `resolve_conditionals` position, updated count from 14 to 16.
- **`main.zig` Zig 0.16 API compatibility** — Fixed `std.io.getStdErr()` to use `std.Io.File.stderr()` for Zig 0.16.

### Changed
- **All 1498 tests pass** with no benchmark regressions.

## [0.199.0] - 2026-08-10

### Added
- **LSP doc hover** — Added `+` doc content to LSP hover popups. Tables, columns, and views now show documentation as markdown blockquote.
- **`enum-value-naming` lint rule** — Warns when custom type enum values use lowercase instead of UPPER_CASE.
- **`fk-null` lint rule** — Warns when foreign key columns are nullable.
- **4 new unit tests** (1498 total).

## [0.198.0] - 2026-08-10

### Added
- **Expanded lint auto-fix** — `rune lint --fix` now supports 8 rules (was 3): serial-type, bool-default, nullable-column-default, duplicate-index, index-column-missing.
- **`LintRule.isFixable()` method** — Rule introspection for fixability status.
- **`template_type_conflict` semantic pass** — Detects table-to-template type mismatches.
- **Auto-lint in `rune migrate`** — Auto-fixes applied to new schema before migration (disable with `--no-lint`).
- **`template_ref` field** — Added to `ResolvedTable` for template tracking.
- **10 new unit tests** (1492 total).

## [0.197.0] - 2026-08-10

### Added
- **49 new tests** for `cli/parse` (argument parsing, flag detection, suggestions) and `lsp/protocol` (JSON-RPC message writing).
- **Consolidated `getInputPath`/`getInputPath2`** into single `getInputPaths` function.
- **Registered new test files** in `tests.zig` comptime index.

## [0.196.0] - 2026-08-10

### Fixed
- **Parser BlockState memory leak** — Fixed `parser/parser.zig` `BlockState.reset()` method that allocated new `parents_buf` without freeing the old one, causing a memory leak on every table/template parse.
- **stripEngineTokens allocation optimization** — Optimized `parser/parse_table.zig` `stripEngineTokens()` to return original tokens when no engine token (`^`) is present, avoiding unnecessary allocation. This eliminated a memory leak in parser tests.

### Changed
- **Extracted docs/format handlers** — Refactored `main.zig` dispatch function by extracting inline `docs` and `format_cmd` command logic into `pipeline/handlers.zig` (`handleDocs`, `handleFormat` functions). Reduced dispatch function by 40 lines while maintaining consistent handler delegation pattern.

## [0.195.0] - 2026-08-10

### Fixed
- **SQLite UNSIGNED test assertion** — Fixed `codegen/columns_test.zig` test that used MySQL backtick quoting (`` `amount` ``) instead of SQLite double-quote quoting (`"amount"`). SQLite uses double quotes for identifiers, not backticks.
- **Mermaid docs memory leak** — Fixed `generators/docs_test.zig` test that leaked 1 allocation from an inner `alloc.dupe` call for test table columns. Added proper `defer alloc.free()`.
- **Parser @if conditional block memory leak** — Fixed `parser/parser_test.zig` test that leaked 15 allocations. Added proper cleanup for field names, modifiers, comments, docs, default values, check constraints, FK declarations, conditional block dialects, and schema-level fields.
- **Parser internal ArrayList buffer leaks** — Added `BlockState.deinit()` method to free ArrayList internal buffers (fields, fks, indexes, conditional_blocks, parents_buf). Added `deinit` calls for parse method's ArrayLists (templates, tables, views, sql_comments, custom_types) after `toOwnedSlice`.
- **stripEngineTokens ArrayList leak** — Added `deinit` call after `toOwnedSlice` in `parse_table.zig` to free ArrayList internal buffer.

### Changed
- **Updated Zig package manager roadmap item** — Marked `build.zig.zon` for dependency consumption as done (v0.195.0).

## [0.193.0] - 2026-08-10

### Fixed
- **WASM diff/migrate compilation bug** — Fixed `rune_diff` and `rune_migrate` in `src/wasm.zig` that called non-existent `diff_engine.computeDiff()` instead of `diff_engine.diff()`. Also fixed argument order mismatch (was `computeDiff(alloc, old, new)`, correct is `diff(old, new, alloc)`). This was a latent compilation error that only manifested under `wasm32-wasi` target.

### Changed
- **Enhanced .ss formatter** — Improved `src/formatter.zig` to properly handle:
  - `@if(dialect=pg|sqlite)` / `@endif` blocks at root level (not indented)
  - `+` doc directives indented at field level inside blocks
  - Block boundary detection when multiple `#` headers appear in sequence
  - Comments inside blocks are now properly indented at field level
- **Fixed formatter test expectations** — Updated `formatter_test.zig` to match correct indentation behavior for comments inside blocks (previously incorrectly expected unindented).

### Added
- **Formatter golden tests** — Added `tests/test_format.sh` with 5 test cases covering basic table formatting, `@if` block formatting, doc directive formatting, template with doc directives, and multiple tables. Also includes `--check` mode tests.
- **Formatter unit tests** — Added 15 inline tests in `src/formatter.zig` covering edge cases for `@if`/`@endif`, doc directives, template syntax, comments, indexes, and blank line handling.

## [0.190.0] - 2026-08-09

### Added
- **Enhanced codegen/columns tests** — Added 14 new tests for column definition rendering: numeric/string/SQL keyword defaults, nullable columns, auto_increment, comments, dialect-specific rendering (MySQL/PostgreSQL/SQLite), and CHECK constraint expressions (range, in_list, comparison).
- **Enhanced pipeline/handlers tests** — Added 4 new tests for `formatValidateResult` covering zero errors, many errors, and valid schemas with views.
- **Enhanced reverse/template_extraction tests** — Added 3 new tests for template extraction: three-table common field detection, partial overlap detection, and empty schema handling.
- **Enhanced parser/parse_template tests** — Added 5 new tests: empty fields, slot at beginning/end, template header parsing (simple template, template with parent, mixin syntax, anonymous template).

## [0.186.0] - 2026-08-09

### Changed
- **Table-driven LSP method dispatch** — Replaced 22-branch if-else chain in `src/lsp/server.zig` with a dispatch table (`DISPATCH_TABLE` array of `{method, handler}` entries). Follows the same pattern used in `cli.zig` with `COMMAND_REGISTRY`. Adding a new LSP method now requires only one entry in the dispatch table and one handler function.
- **Data-driven lint rule dispatch** — Replaced 22 repetitive guard-then-call blocks in `src/lint/rules.zig:runAll()` with a data-driven dispatch table (`RULES` array of `{rule, handler}` entries). Each handler receives the full AST + config and iterates over relevant entities internally. Reduces `runAll` from ~80 lines to ~15 lines.
- **PassContext.init() method** — Added `init()` method to `PassContext` in `src/semantic/pass_manager.zig` for explicit, safe initialization. The `undefined` defaults are preserved for backward compatibility with existing code, but `init()` is preferred for new code.
- **WASM error reporting** — Added `rune_last_error()` export to `src/wasm.zig` that returns the last error message from `rune_compile()`. Host environments can now distinguish between parse errors, semantic errors, and codegen errors instead of receiving null.

### Added
- **Table-level rename detection** — Added rename detection in `src/diff/engine.zig` that matches dropped tables with created tables when field overlap exceeds 70%. Renamed tables are reported as `RENAME TABLE old → new` instead of `DROP TABLE old` + `CREATE TABLE new`. Added `rename_from` field to `TableDiff` struct.
- **Rename display in diff formatters** — Updated text, JSON, and SARIF diff formatters to show table rename information. Text format shows `-- RENAME TABLE old → new`, JSON includes `rename_from` field, SARIF includes `schema/renamed-table` rule.

## [0.185.0] - 2026-08-09

### Fixed
- **Test compilation errors** — Fixed 2 compilation errors in test code:
  - `src/codegen/codegen.zig`: Changed `std.Thread.Mutex` to `std.atomic.Mutex` for Zig 0.16 compatibility (std.Thread.Mutex doesn't exist in Zig 0.16.0)
  - `src/codegen/parallel.zig`: Changed `.varchar_explicit = 255` to `.{ .varchar = 255 }` (varchar_explicit is not a variant of SqlType union)
- **Fragile `undefined` in PassContext** — Fixed `src/semantic/pass_manager.zig` PassContext by initializing `symbol_table` field with empty `SymbolTable` in analyzer (was `undefined`, could cause garbage data if accessed before resolve_names pass)
- **`--check` mode in reverse pipeline** — Fixed `src/pipeline/reverse.zig` `--check` mode to produce meaningful output ("SQL is valid") instead of silently returning without output

### Changed
- **Verified 1362 tests pass** — All unit tests pass after fixes

## [0.182.0] - 2026-08-09

### Added
- **Enhanced pass_manager tests** — Added 5 new tests for `validatePassAccess()`, unique pass name validation, dependency validation, writer dependency verification, and access default validation. `pass_manager_test.zig` now covers all pass manager functionality.
- **CLI lint_cmd unit tests** — Added `cli/lint_cmd_test.zig` with 3 tests covering `LintCmd` struct initialization, default values, and custom value handling.
- **CLI init unit tests** — Added `cli/init_test.zig` with 9 tests covering template selection (default, blog, ecommerce, rest-api), unknown template handling, and STARTER_SCHEMA content validation.
- **Parser sql_parser_helpers tests** — Added `parser/sql_parser_helpers_test.zig` with 35+ tests covering word parsing, string literals, default values, expression parsing, comment handling, whitespace skipping, keyword matching, and line/column tracking.

### Changed
- **Fixed build.zig.zon version** — Updated version from `0.180.0` to `0.182.0` to match VERSION file. This fixes `rune --version` output.
- **Updated npm package version** — Synced `packaging/npm/package.json` from `0.176.0` to `0.182.0`.

## [0.180.0] - 2026-08-09

### Added
- **`index-column-missing` lint rule** — Warns when an index references columns that don't exist in the table. Catches typos and schema drift in index definitions.
- **`naming-prefix` lint rule** — Warns about table names using anti-pattern prefixes (`tbl_`, `t_`, `tb_`, `table_`). Helps enforce clean naming conventions.

### Changed
- **Improved `toCamelSingular` pluralization** — Handles irregular plurals (men→man, women→woman, children→child, people→person, data→datum), -ies→-y (categories→category, companies→company), doubled consonants (quizzes→quiz, addresses→address), and -ves (knives→knife, lives→life). Was previously limited to naive trailing-'s' strip.
- **Extended lint engine** — Lint rule count increased from 18 to 20. All new rules are enabled by default and configurable via `rune-lint.toml`.

## [0.179.0] - 2026-08-09

### Added
- **`rune validate --format json`** — Machine-readable JSON output for CI/CD pipelines. Outputs `{"valid":bool,"errors":int,"tables":int,"fields":int,"views":int}` for both valid and invalid schemas.
- **`rune reverse --check`** — CI gate mode for SQL schema validation. Exits silently with code 0 on valid SQL, exits with code 1 on parse errors. Aligns with `rune diff --check` and `rune migrate --check` patterns.
- **`rune check --format json`** — JSON output support for the check command (CI gate mode).
- **`column-length` lint rule** — Warns when string fields (`s`, `S`) lack explicit length specification. Helps catch cross-dialect compatibility issues (MySQL TEXT vs PostgreSQL unlimited VARCHAR). Configurable via `rune-lint.toml`.

### Changed
- **Extended validate command** — Added `--format` flag (text, json) to `rune validate` and `rune check` commands for structured output.
- **Extended reverse command** — Added `--check` flag to `rune reverse` for validation-only CI gate mode.

## [0.178.0] - 2026-08-09

### Changed
- **Simplified io.zig file reading** — Removed mmap-based large file optimization from `readFileOrStdin` that was duplicating memory (mmap → alloc.dupe). All file reads now use `readFileAlloc` directly, eliminating the unnecessary copy. The mmap utility (`mmapFile`) remains available as a public API for callers that need it directly.
- **Proper mmap cleanup on Linux** — `MmapResult.deinit()` now calls `munmap` on Linux for proper resource cleanup, fixing a memory leak in long-running processes (LSP server).

### Added
- **TypedAst IR unit tests** — Added 17 tests for `ColumnFlags` packed struct, `TypedColumn`, `TypedTable`, `TypedView`, and `TypedAst` initialization (was zero coverage).
- **ResolvedAst IR unit tests** — Added 11 tests for `ResolvedTable` and `ResolvedAst` initialization (was zero coverage).
- **Architecture docs** — Added `tune.zig` and `watch.zig` module documentation to ARCHITECTURE.md (shipped in v0.172.0 and v0.163.0 respectively).

## [0.177.0] - 2026-08-09

### Changed
- **Unified type classification** — Added `TypeCategory` enum (`numeric`, `string`, `datetime`, `boolean`, `blob`, `other`) to `types/ast.zig`. `TypeInfo.category()` method consolidates the 4 `is*` methods into a single source of truth. `categoryFromSym()` function provides raw symbol classification for both forward and reverse pipelines.
- **REVERSE_MAP category auto-computation** — Added `rev()` helper function to `types/reverse_map.zig` that auto-computes `category` from `sym` at comptime. All 80+ REVERSE_MAP entries now use `rev()` instead of raw struct literals, eliminating manual category maintenance.
- **ReverseMapping.category field** — Added `category: TypeCategory` field to `ReverseMapping` struct, enabling category-based queries on reverse mapping entries.

### Fixed
- **TypeInfo blob classification** — `B` (blob) is now correctly classified as `.blob` category instead of `.string`. The old `isString()` method incorrectly treated blob types as string types.
- **TypeInfo raw_sql classification** — `raw_sql` passthrough types are now classified as `.other` instead of `.string`, since their semantic category depends on the actual SQL type string.

## [0.175.0] - 2026-08-09

### Fixed
- **TypeORM duplicate index branch** — Removed identical if/else branches in `typeorm.zig` that produced the same output for both unique and regular single-column indexes.
- **Windows file URI handling** — `uriToPath` in `documents.zig` now correctly strips the leading `/` from Windows `file:///C:/path` URIs.

### Changed
- **Generator deduplication** — Extracted `shouldEmitDefault` helper into `generators/common.zig`, replacing 6 inline default value checks across drizzle, knex, sqlalchemy, typeorm, and prisma generators.
- **Removed 4 redundant `writeDefault` wrappers** — drizzle, knex, sqlalchemy, and typeorm generators now call `common.writeFormattedDefault` directly, eliminating 16 lines of passthrough boilerplate.
- **LSP shared `findNameInLine`** — Extracted identical name-finding logic from `highlights.zig` and `references.zig` into `lsp/helpers.zig`, eliminating 50 lines of duplication.
- **Removed `reverse/map_data.zig` shim** — 4-line re-export indirection eliminated; `reverse/map.zig` and `dialect/sqlite.zig` now import directly from `types/reverse_map.zig`.

### Added
- **`common.shouldEmitDefault`** — Shared predicate for checking if a default value should be emitted in ORM output (non-empty and not "null"). 3 new tests added.
- **LSP helpers test coverage** — `findNameInLine` is now tested via the existing LSP test suite through both highlights and references paths.

## [0.174.0] - 2026-08-09

### Fixed
- **LSP references precise column ranges** — FK references now highlight only the FK field name (e.g., `user_id`) instead of the entire line. Added `findNameInLine` helper to scan document text for exact name positions.
- **LSP highlights precise column ranges** — FK reference highlights now use precise column ranges instead of full-line ranges. Added `findNameInHighlights` helper for consistent name matching.
- **LSP go-to-definition multi-column FK** — `getDefinition` now checks all FK fields (`fk.fields`) instead of only the first field (`fk.fields[0]`). Multi-column FKs like `(user_id, role_id) -> (users.id, roles.id)` now navigate correctly from any FK field.
- **LSP document_symbols column range** — Column `range` now ends at the column name length instead of extending to character 100, providing precise selection ranges in the outline view.

### Changed
- **LSP hover dialect-aware SQL types** — `getHover` now accepts a `Dialect` parameter. Column hover shows dialect-specific SQL types (e.g., `INT` for MySQL, `integer` for PostgreSQL) instead of generic Zig enum tag names. FK target column type display is also dialect-aware.
- **LSP features facade** — `features.zig` now imports and re-exports `Dialect` enum for type-safe dialect parameter passing.

### Added
- **LSP FK feature tests** — Added 4 new tests covering FK-related LSP features: references with FK precise ranges, highlights with FK precise ranges, go-to-definition with multi-column FK, and hover with dialect-specific SQL types.

## [0.173.0] - 2026-08-09

### Fixed
- **LSP writeCodeAction hardcoded URI** — Replaced `"file:///"` literal with actual document URI in `writeCodeAction` JSON serialization. Previously, all code actions referenced a non-existent `file:///` path instead of the correct document.
- **LSP magic number 100 for range ends** — Replaced hardcoded `character = 100` in `references.zig` and `highlights.zig` with actual line length computed from document text via shared `getLineText` helper.

### Changed
- **LSP shared utilities** — Extracted `getLineText`, `lineLength`, and `formatFlagsForHover` into `lsp/helpers.zig` as shared utilities. `hover.zig` no longer duplicates flag formatting logic.
- **LSP dynamic arrays** — Replaced static 256-element arrays in `references.zig` and `highlights.zig` with allocator-based `ArrayList`, eliminating silent truncation for schemas with many references.
- **Parser shared `locFromLine`** — Extracted duplicated `locFromLine` function into shared `parser/loc.zig` module. `parse_table.zig`, `parse_template.zig`, and `parse_recovery.zig` now import from the shared location.

## [0.170.0] - 2026-08-09

### Added
- **Lint rule: serial-type** — Warns when using PostgreSQL-specific `serial`/`bigserial` types in schemas. Recommends using `auto_increment` modifier for cross-dialect compatibility.
- **Lint rule: table-name-length** — Warns when table names exceed a configurable length (default: 64 chars). Some databases have hard limits on table name length.
- **LSP features facade tests** — Added comprehensive tests for the LSP features module covering document symbols, hover, completions, go-to-definition, references, and document highlights.

### Changed
- **Lint config** — Added `check_serial_type`, `check_table_name_length`, and `table_name_max` fields to `LintConfig`. Added `table_name_max` threshold to `LintRulesConfig`.

## [0.169.0] - 2026-08-08

### Fixed
- **MSSQL IDENTITY parsing** — Fixed SQL parser to recognize MSSQL's `IDENTITY(seed, increment)` syntax as a column modifier. Previously, `IDENTITY` was mis-parsed as a separate column name, producing phantom `IDENTITY (1,1) ?` entries in reverse-engineered `.ss` output.
- **MSSQL auto_increment codegen** — Implemented `emitAutoIncrement` for MSSQL backend to emit `IDENTITY(1,1)` in forward codegen. Previously, auto_increment columns in MSSQL output had no identity clause.

### Changed
- **MSSQL reverse golden files** — Updated all 3 MSSQL reverse test golden files to match corrected parser behavior: `id n !` → `id n ++` (auto_increment + primary_key), removed phantom `IDENTITY (1,1) ?` columns.

## [0.168.0] - 2026-08-08

### Fixed
- **DocumentManager memory leak** — Fixed memory leak in `lsp/documents.zig` where reopening a document leaked the URI allocation. The `open()` function now properly frees the duplicate URI when replacing an existing document.

### Added
- **LSP compile service tests** — Added 3 new tests for the LSP compile service covering syntax errors, semantic errors, and multiple FK references. Tests verify the pipeline handles edge cases without crashing.
- **Pipeline edge case tests** — Added 3 new tests for `compilePipeline` covering empty input, comments-only input, and whitespace-only input.
- **LSP hover FK enhancements** — Hover over a foreign key now shows the target column's type and constraints (PRIMARY KEY, NULLABLE/NOT NULL) in addition to the existing relationship info.

### Changed
- **Documentation** — Updated README to list all LSP features including references, highlights, and rename.

## [0.167.0] - 2026-08-08

### Changed
- **LSP protocol split** — Extracted JSON serialization utilities (`writeJsonString`, `writeJsonField`, `writeJsonValue`, etc.) from the 952-line `lsp/protocol.zig` monolith into `lsp/json.zig` (~170 lines). Extracted JSON-RPC message parsing (`parseMessage`, `ParsedMessage`, `cloneValue`, `freeJsonValue`, field extractors) into `lsp/message.zig` (~170 lines). `protocol.zig` now re-exports all symbols for backward compatibility, reduced from 953 to ~530 lines.

### Added
- **MSSQL reverse engineering tests** — Added `test_reverse_mssql.sh` with 3 test cases covering basic table reverse, type mapping (NUMERIC, BIT, DATETIME2, NVARCHAR), and FK reverse engineering. Added to `test_coverage.sh` suite list.

## [0.166.0] - 2026-08-08

### Fixed
- **`generateTypedView` buffer leak** — Added `defer buf.deinit()` to the UNION/INTERSECT/EXCEPT view codegen path in `codegen/codegen.zig`. Previously, every set-operation view leaked an allocating writer buffer.
- **`StreamingCodegen` resource leak** — Added `deinit()` method to `StreamingCodegen` in `codegen/streaming.zig` that properly frees the underlying `Codegen` struct via `alloc.destroy()`. Added `defer sc.deinit()` at all 4 call sites in `codegen/parallel.zig` (3 sequential fallback paths + view compilation loop). Previously, the view loop leaked one `Codegen` allocation per view.

### Changed
- **BufferPool for default SQL codegen** — Modified `handleCompileRequest` in `pipeline/handlers.zig` to use `BufferPool` + `generateFromTypedAstPooled` for the default (non-streaming) `.sql` format path, reusing the same pool pattern already used in streaming mode.
- **Packaging manifest sync** — Updated all 6 packaging manifests from v0.159.0 to v0.166.0: `VERSION`, `build.zig.zon`, `npm/package.json`, `homebrew/rune.rb`, `scoop/rune.json`, `vscode/package.json`.

### Added
- **View codegen tests** — 6 new unit tests in `codegen/codegen_test.zig` covering simple views, UNION ALL, UNION DISTINCT, INTERSECT, EXCEPT, and views with comments. All 4 set-operation variants are now tested across MySQL and PostgreSQL dialects.

## [0.165.0] - 2026-08-08

### Changed
- **DialectBackend vtable: pointer return** — `getBackend()` now returns `*const DialectBackend` instead of copying 136 bytes on every call. Updated `Codegen.backend`, `MigrationContext.backend`, and all codegen/migration emission functions to use pointers throughout.
- **MigrationContext struct** — Replaced 9-parameter function signatures in `diff/migrate.zig` with a single `MigrationContext` struct, reducing parameter bloat across 8 emit* functions.
- **LintRule enum** — Introduced `LintRule` enum in `lint/config.zig` with `isEnabled()`, `name()`, and `fromName()` methods. Updated `runAll()` and `fixAll()` to use `LintRule.isEnabled()` instead of direct config field access.
- **applyLintRules refactor** — Replaced 24-line string comparison chains with `LintRule.fromName()` + `setRuleEnabled()` dispatch, reducing duplication and making new rules a single enum addition.
- **Comptime dialect validation** — Replaced 31+ manually-maintained `@compileError` lines with `comptimeValidateAllPointers()` that auto-validates all function pointer fields via struct iteration.

## [0.164.0] - 2026-08-08

### Added
- **LSP find-references** — `textDocument/references` support for finding all references to a table or column name across the document.
- **LSP document highlights** — `textDocument/documentHighlight` support for highlighting all occurrences of the symbol under the cursor.
- **Lint auto-fix: empty-table** — `rune lint --fix` now removes empty table declarations (tables with zero fields).
- **Lint fix tests** — Unit tests for the lint auto-fix module covering no-pk, no-timestamps, and empty-table rules.

### Fixed
- **LSP compile_service memory leak** — Fixed leaked allocations in `lsp/compile_service.zig` by using arena allocation for pipeline intermediates and freeing tokenizer output after semantic analysis. Tests now use arena allocators matching the LSP server's actual usage pattern.
- **import_resolver memory leak** — Fixed leaked DiagnosticCollector in `tokenizeAndParseWithLines` by adding proper cleanup.

## [0.163.0] - 2026-08-08

### Added
- **Watch directory mode** — `rune watch ./schemas --recursive` watches all `.ss` files in a directory (with optional recursion). Tracks per-file hashes and recompiles only changed files. Prints directory summary with file count and error streak tracking.
- **Init template presets** — `rune init myapp --template blog|ecommerce|rest-api` generates predefined starter schemas. Templates: `default` (users/posts), `blog` (posts/categories/tags/comments), `ecommerce` (products/orders/customers), `rest-api` (resources/endpoints/api-keys/audit-log).

## [0.162.0] - 2026-08-08

### Changed
- **Pipeline split & optimization** — Extracted output handlers from `pipeline/forward.zig` (520 lines) into `pipeline/handlers.zig` (270 lines) for single-responsibility.
- **Index validation optimization** — Optimized O(n²) column lookups in `validate_indexes.zig` to O(n) via StringHashMap.
- **Handler tests** — Added tests for `pipeline/handlers.zig` (formatValidateResult).

## [0.161.0] - 2026-08-08

### Changed
- **Lint test split** — Split `lint_test.zig` monolith (1,018 lines) into 3 focused test files: `lint/rules_test.zig`, `lint/format_test.zig`, `lint/config_test.zig`.
- **LSP handler extraction** — Extracted LSP request handlers from `server.zig` into `handlers.zig`.
- **Tests.zig organization** — Added section comments to `tests.zig` for easier navigation.

### Documentation
- **ARCHITECTURE.md** — Documented lint module structure and sub-module responsibilities.

## [0.160.0] - 2026-08-07

### Changed
- **Lint module split** — Extracted 1017-line `lint.zig` monolith into 4 focused sub-modules: `lint/rules.zig` (15 lint rule implementations), `lint/format.zig` (text/JSON/SARIF formatters with shared `writeJsonString` helper), `lint/config.zig` (LintConfig, TOML parsing, diff-aware comparison), `lint/fix.zig` (auto-fix for no-pk and no-timestamps).
- **Lint CLI handler extraction** — Moved ~110-line lint command handler from `main.zig:dispatch()` into `cli/lint_cmd.zig`, following the existing `cli/init.zig` and `cli/hooks.zig` pattern.
- **`main.zig` simplified** — Lint command dispatch reduced from ~110 lines to ~12 lines (struct literal construction + delegation).

## [0.159.0] - 2026-08-07

### Fixed
- **Version synchronization** — Aligned all packaging files (build.zig.zon, Homebrew, npm, Scoop, VS Code) to the correct version.
- **LSP test registration** — Registered 8 LSP modules in `tests.zig` so `zig build test` compiles and runs them.
- **LSP memory leaks** — Fixed memory leaks in `hover.zig` (flags_str, ArrayList), `document_symbols.zig` (children, detail), and `protocol.zig` (ParsedMessage.deinit).
- **LSP ownership bugs** — Changed `getCompletions`, `getDocumentSymbols`, and `getCodeActions` to use `toOwnedSlice` instead of `.items` for proper ownership transfer.
- **LSP empty struct serialization** — Fixed `writeJsonValue` to output `{}` for empty structs instead of nothing.
- **Grammar documentation** — Added missing `type_def_decl` (`~`) and `engine_decl` (`^`) rules to `grammar.ebnf`.

### Added
- **LSP unit tests** — Added `freeJsonValue`, `ParsedMessage.deinit`, `freeDocumentSymbols`, and `freeCodeActions` helpers for proper test cleanup.

## [0.158.0] - 2026-08-07

### Added
- **Lint auto-fix** — `rune lint --fix` auto-corrects no-pk and no-timestamps issues.
- **Lint dry-run** — `--dry-run` preview mode shows fixes without writing.
- **Init output-dir** — `rune init --output-dir` creates starter schemas in subdirectories.

## [0.157.0] - 2026-08-07

### Fixed
- **OpenAPI generator extension** — Changed from `.yaml` to `.json` to match actual output format (OpenAPI 3.1 JSON).
- **LSP `wordAtCursor` bug** — Fixed function returning empty string on first character of each line instead of processing to cursor position. Now correctly extracts the word at the cursor position.
- **LSP `detectContext` bug** — Same fix as `wordAtCursor`: now processes the full line instead of returning on the first character.
- **LSP `aw.pos` deprecation** — Replaced `aw.pos = 0` with `aw.clearRetainingCapacity()` in protocol.zig tests for Zig 0.16 compatibility.
- **LSP `hover.zig` union syntax** — Fixed `.varchar` to `.{ .varchar = 255 }` for Zig 0.16 tagged union syntax.
- **LSP `code_actions.zig` severity** — Fixed `.info` to `.information` for `DiagnosticSeverity` enum.

### Added
- **Generator CHECK constraint tests** — New `generators/common_check_test.zig` with 15 tests for `parseRange`, `parseComparison`, and `parseInList`.
- **Generator default formatting tests** — New `generators/common_defaults_test.zig` with 16 tests for `writeFormattedDefault` and `getOrmFormatter` across all ORM targets.
- **Benchmark baseline refresh** — Updated baselines for all 6 dialects to fix `type_resolve` regression noise.

## [0.156.0] - 2026-08-07

### Added
- **`rune format --check`** — New `--check` flag for the format command. Verifies formatting without modifying files; exits with code 1 if the file needs formatting. Designed for CI/CD pipelines.

### Fixed
- **Config discovery error swallowing** — `rune.toml` discovery now propagates filesystem errors (e.g. `AccessDenied`, `IsDir`) instead of silently returning an empty config. The caller still falls back to defaults with a warning.
- **LSP formatting error logging** — `lsp/formatting.zig` now logs formatting errors to the LSP output channel before returning null, instead of silently swallowing them.
- **`catch unreachable` in test helpers** — Replaced `catch unreachable` with `try` in `validate_index_names.zig` and `streaming_test.zig` for proper OOM error propagation.

## [0.155.0] - 2026-08-07

### Fixed
- **Migration guide syntax errors** — Replaced invalid `*`/`^` modifiers with actual parser syntax (`n++`, `!`, `@u`, `?`).
- **Packaging manifests** — Updated Homebrew formula, Scoop manifest, and npm package.json to v0.155.0.
- **Benchmark baselines** — Saved baselines for all 6 dialects (pg, sqlite, mssql, oracle, db2).

## [0.154.0] - 2026-08-07

### Changed
- **LSP Features Modularization** — Split monolithic `lsp/features.zig` (1491 lines) into 7 focused sub-modules: `document_symbols.zig`, `completions.zig`, `hover.zig`, `go_to_definition.zig`, `code_actions.zig`, `rename.zig`, `formatting.zig`. `features.zig` is now a thin facade re-exporting all sub-modules. No API changes for callers.
- **Parallel Compilation Deduplication** — Extracted `compileGroupConcurrent` helper from `codegen/parallel.zig`, eliminating ~100 lines of duplicated thread spawn/join/collect/fallback logic across batch processing paths.
- **Removed Dead Code** — Deleted `diff/invert.zig` (132 lines) which duplicated inversion logic already in `diff/plan.zig`. Migrated 4 unit tests (`invertFieldDiff` cases) to `plan.zig`. Updated `tests.zig` index.

### Added
- **LSP Helpers Module** — New `lsp/helpers.zig` with shared `makeRange` utility used by all LSP sub-modules.

## [0.153.0] - 2026-08-07

### Added
- **VS Code LSP Integration** — Extension now starts the Rune language server (`rune lsp`) via `vscode-languageclient`. Enables real-time diagnostics, completion, hover, go-to-definition, code actions, and document formatting directly in VS Code. New settings: `rune.schemaPath` (custom binary path), `rune.lspEnabled` (toggle LSP).
- **esbuild Bundling** — New `packaging/vscode/esbuild.js` bundles the extension with `vscode-languageclient` into `dist/extension.js`. Build with `npm run build`, package with `npm run package`.
- **LSP Tests** — 3 new tests in `lsp/features.zig`: `CodeActions: multiple diagnostics`, `Hover: column hover`, `DocumentSymbols: multiple tables`. Total LSP tests: 35.

### Fixed
- **LSP handleCodeAction bug** — `lsp/server.zig` `handleCodeAction` used a zero-length fixed array for diagnostics, silently dropping all client-provided diagnostic context. Replaced with `std.ArrayList(Diagnostic)` so code actions now correctly receive and use the editor's diagnostic context.
- **LSP code action placeholder** — The "Add table comment" code action in `lsp/features.zig` inserted `# TODO: add description` as replacement text. Changed to `# Add a description here`.

## [0.151.0] - 2026-08-07

### Added
- **TextMate Grammar** — New `packaging/vscode/syntaxes/rune.tmLanguage.json` with comprehensive syntax highlighting for `.ss` schema files. Covers all declaration types (`$`, `~`, `%`, `#`, `&`, `>`, `@`, `!`), type symbols, modifiers, literals, comments, and SQL expressions.
- **VS Code Extension** — New `packaging/vscode/` with `package.json`, `language-configuration.json`, and `extension.js`. Registers Rune language, TextMate grammar, and commands (`Rune: Validate`, `Rune: Generate SQL`, `Rune: Initialize Schema`). Activation on `.ss` file open.
- **Language Configuration** — Bracket matching, auto-closing pairs, folding markers, and comment toggling for `.ss` files.

### Changed
- **npm version sync** — `packaging/npm/package.json` version aligned with VERSION file.

## [0.150.0] - 2026-08-07

### Added
- **Docker Image** — New `Dockerfile` with multi-stage build (builder + runtime). Multi-arch support (linux/amd64, linux/arm64). Published to `ghcr.io/rune-lang/rune:latest`. New GitHub Actions workflow (`.github/workflows/docker.yml`) for automated builds on release tags.
- **Migration Guide** — New `docs/migration-guide.md` with comprehensive migration instructions from SQL DDL, Prisma, and Knex. Includes symbol reference table, step-by-step migration process, and practical tips for incremental migration.
- **Package Manager Support** — New Homebrew formula (`packaging/homebrew/rune.rb`), Scoop manifest (`packaging/scoop/rune.json`), and npm package (`packaging/npm/`). npm package includes postinstall script that downloads the correct platform binary.

### Changed
- **Distribution** — Updated README with Docker usage instructions, package manager installation options, and link to migration guide.

## [0.149.0] - 2026-08-07

### Added
- **FlagRegistry Pattern** — New `cli/flag_registry.zig` with `GLOBAL_FLAG_REGISTRY` array defining all global CLI flags in one place. `parseGlobalFlags` now uses `flag_reg.matchesFlag()` for boolean flag detection, replacing repetitive raw `std.mem.eql` chains. Added `isKnownGlobalFlag()` for unknown-flag detection. Barrel re-exports from `cli.zig`. 3 unit tests for flag matching.
- **Weighted Confidence Scoring** — `reverse/map.zig` now applies naming-convention bonuses to reverse engineering confidence scores: +5 for snake_case column names, +3 for semantic suffixes (`_id`, `_at`, `_on`, `_name`, `_key`, `_ts`), +3 for boolean prefixes (`is_`, `has_`, `can_`, `was_`, `should_`). Scores capped at 100. 7 new unit tests for `computeConfidence` and updated score expectations.
- **Test Suite Sync** — `tests/test_coverage.sh` now includes all 30 golden test suites (was 24): added TypeORM, SQLAlchemy, Knex, Color, Lint, and Parallel suites.

### Changed
- **CLI Parsing** — `isKnownLongFlag` now checks both `GLOBAL_FLAG_REGISTRY` and `KNOWN_FLAGS` for comprehensive flag detection.
- **Confidence Score Expectations** — Updated 11 existing score tests in `reverse/map_test.zig` to reflect weighted scoring (e.g., `varchar(128)` on `user_name` now returns 93 instead of 85 due to snake_case + suffix bonuses).

## [0.148.0] - 2026-08-07

### Added
- **ErrorFormatter Integration** — Wired `diagnostic/format.zig` ErrorFormatter into `main.zig` and `pipeline/forward.zig`. All CLI error output now uses standardized `error[rule]: message` format with category rules (`cli`, `config`, `io`, `schema`, `sql-parse`). Added `printErr` and `printWarn` convenience functions for messages without rule codes.
- **CLI Consolidation** — Extracted shared `parseSimpleSubcommand` helper into `cli/parse.zig`. Removed duplicate definitions from `cli/parse_compile.zig` and `cli/parse_utils.zig`, eliminating ~30 lines of duplicated code.
- **Confidence Score Constants** — Extracted `CONFIDENCE_THRESHOLD = 80` named constant in `reverse/column.zig`, replacing magic number in `writeColumnConfidence`.
- **Confidence Score Improvements** — `reverse/map.zig` now returns explicit confidence scores: 85 for standard parameterized types (`varchar(128)`, `decimal(10,2)`), 60 for ENUM passthrough, 50 for unknown types and oversized parameters. Previously all defaulted to 100.
- **New tests**: 3 new unit tests in `reverse/map_test.zig` covering unknown type fallback, ENUM passthrough confidence, and varchar(255) cross-dialect match.

### Changed
- **Reverse Engineering** — `writeColumnConfidence` guard condition simplified: removed redundant `col.comment != null and` check.
- **CLI Error Messages** — Config validation, parse errors, dispatch errors, and schema compilation errors now use `ErrorFormatter` with structured rule codes instead of raw `std.debug.print("error: ...")`.

## [0.147.0] - 2026-08-07

### Added
- **Generator Duplication Consolidation** — Extracted shared table schema writing logic from `openapi.zig` and `json_schema.zig` into `generators/common.zig:writeTableSchemaJson()`. Eliminates ~50 lines of duplicated code and ensures consistent output across JSON Schema and OpenAPI generators.
- **TypeORM Golden Tests** — New `tests/test_typeorm.sh` test suite with 2 golden tests covering basic table generation and FK relationships.
- **SQLAlchemy Golden Tests** — New `tests/test_sqlalchemy.sh` test suite with 2 golden tests covering basic table generation and FK relationships.
- **Knex Golden Tests** — New `tests/test_knex.sh` test suite with 2 golden tests covering basic table generation and FK relationships.
- **Error Formatting Module** — New `diagnostic/format.zig` with `ErrorFormatter` struct providing standardized error message formatting: `formatError(rule, message)` → `"error[{rule}]: {message}"`.

### Changed
- **Generator Architecture** — `openapi.zig` and `json_schema.zig` now delegate table schema writing to `common.writeTableSchemaJson()`, reducing maintenance burden and ensuring feature parity.

## [0.146.0] - 2026-08-07

### Added
- **LSP Code Actions** — New `textDocument/codeAction` support provides quick fixes for common schema issues. Includes: missing primary key (suggest adding `++`), missing table comment (suggest adding comment), naming convention violations (suggest snake_case rename). Server now advertises `codeActionProvider` capability.
- **LSP Dialect Configuration** — LSP server now accepts `initializationOptions.dialect` during `initialize` handshake. Editors can configure the target SQL dialect (mysql, pg, sqlite, mssql, oracle, db2) for type resolution instead of defaulting to MySQL.
- **Context-sensitive Completion** — `textDocument/completion` now filters suggestions based on cursor context. Inside table bodies: type symbols and modifiers. After `FK` keyword: table names and FK references. After `%`: template names. Top level: keywords only.
- **LSP Document Formatting** — New `textDocument/formatting` support formats `.ss` files using the `rune format` engine. Server now advertises `documentFormattingProvider` capability.
- **New tests**: 7 new unit tests in `features.zig` covering code actions (empty diagnostics, missing PK suggestion), snake_case conversion, and context-sensitive completion (top level, inside table). Total: ~1147 tests.

### Changed
- **LSP Compile Service** — `compile()` now accepts a `Dialect` parameter instead of hardcoding MySQL. Threaded from server's `initializationOptions` through to type resolution.

## [0.137.0] - 2026-08-06

### Added
- **Expanded lint rules** — 3 new rules: `wide-table` (warns when table has >30 fields), `enum-case` (warns when custom types use non-UPPER_CASE naming), `count` (warns when table has <2 non-PK fields).
- **SARIF output** — `rune lint --format sarif` produces SARIF 2.1.0 for CI/CD integration.
- **Diff-aware lint** — `rune lint old.ss new.ss` compares lint results, outputs only newly introduced issues.
- **Lint rules config** — `rune-lint.toml` configuration file for customizing lint behavior. New `--rules <path>` flag.
- **15 new unit tests** covering all new rules, SARIF output, diff-aware lint, and config parsing.

## [0.127.0] - 2026-08-05

### Added
- **Watch command feature parity** — `rune watch` now supports `--trace`, `--stats`, `--json-errors`, and `--parallel` flags. All compilation options are now consistent between `rune <file>` and `rune watch <file>`.
- **Watch subcommand help** — `rune watch --help` now displays all available options.
- **Shell completions expansion** — Added `--parallel`, `--interval`, `--stream`, `--summary`, `--config`, `--name`, `--dir`, `--incremental`, `--graph` flags to Bash, Fish, and PowerShell completions. Added `symbol-index` generator to all 4 shell completion scripts. Zsh completions now offer watch-specific flag completions.

### Fixed
- **Build dependency fix** — Removed unnecessary `b.getInstallStep()` dependency from test targets in `build.zig`. Unit tests no longer require the rune binary to be installed first, eliminating Windows file locking conflicts during test runs.

## [0.122.0] - 2026-08-05

### Added
- **Real parallel table compilation** — `codegen/parallel.zig` now uses `std.Thread` to compile independent table groups concurrently. Each thread uses its own arena allocator for thread safety. New `max_threads` config option (default: 4).
- **5 new unit tests** for parallel compilation covering `findGroups`, sequential fallback, concurrent path, and topological ordering.

### Fixed
- **Memory leaks in bench.zig** — `parseFileTimed` and `parseFile` now properly `defer lines.deinit(alloc)`.
- **errdefer patterns in diff engine** — Added `errdefer` to `ArrayList` allocations in `diff/engine.zig`, `diff/fields.zig`, `diff/fks.zig`, and `diff/indexes.zig` to prevent leaks on error paths.

### Changed
- **Documentation sync** — Fixed stale "8 passes" → "11 passes" and "4 dialect backends" → "6 dialect backends" in README.md. Updated CLAUDE.md parallel compilation description.

## [0.118.0] - 2026-08-05

### Changed
- **Expanded diagnostic test coverage** — 7 new unit tests for `DiagnosticCollector`: `formatTerminal` output verification, empty output, `hadOom` accessor, `record` alias, JSON escaping of special characters, and LSP 0-based line number conversion.
- **ROADMAP sync** — Marked `rune watch` as done in Phase 4. Updated summary counts (60/81 done).

## [0.106.0] - 2026-08-04

### Fixed
- **Streaming compilation includes views and comments** — `rune schema.ss --stream` now properly includes views and SQL comments in the output. Previously, views and comments were silently skipped (data loss bug). `StreamingResult` now includes `views` and `comments` fields with line numbers for proper interleaving.
- **Stats field naming** — Renamed `Stats.templates` to `Stats.custom_types` to accurately reflect that the field counts custom type definitions (`~` directives), not templates (`%` definitions). Templates are resolved during semantic analysis and don't appear in the resolved AST. JSON output key changed from `"templates"` to `"custom_types"`.
- **Unused dialect parameter removed** — Removed the unused `dialect` parameter from `typeInfoEqualDialect`, `fieldSignatureMatch`, `fieldsEqual`, `diffFields`, `diffTable`, and `diff` functions in the diff engine. The dialect parameter was a dead code path since the underlying `typeInfoEquiv` is dialect-agnostic.
- **Migrate status JSON optimization** — Replaced O(n²) hand-rolled JSON string concatenation with streaming `std.Io.Writer.Allocating` approach using the existing `utils.jsonEscapeString` helper. Also optimized the non-JSON text output path.
- **`emitCheckExpr` relocated** — Moved `emitCheckExpr` from `codegen/codegen.zig` to `codegen/columns.zig` where it belongs (CHECK expression rendering is part of column definition codegen). Backward-compatible re-export maintained in `codegen.zig`.

### Added
- **Streaming compilation tests** — 4 new unit tests covering views, comments, interleaving, and `formatStreamingResult` output ordering.

### Changed
- Updated test suite for stats JSON (3 tests) and migrate status (7 tests).

## [0.99.0] - 2026-08-03

### Fixed
- **`migrate status` 4-digit prefix bug** — `handleMigrateStatus` now correctly handles both 3-digit (legacy) and 4-digit migration file prefixes. Previously used `lastIndexOfScalar` which found the wrong underscore position for filenames like `0001_add_users.sql`. Changed to `indexOfScalar` for correct first-underscore detection.
- **Iterator string lifetime** — Directory entries are now duplicated before storage (`alloc.dupe`), preventing stale pointers when the iterator reuses its internal buffer.

### Added
- **`migrate status --json-errors`** — Machine-readable JSON output for migration file listing. Outputs `{"files":[{"name":"...","label":"..."},...],"count":N}`.
- **`rune diff --summary`** — Output only the summary line (`N tables changed (X added, Y dropped, Z modified)`) without the full diff. Useful for CI checks and commit messages.
- **New test suite** — `tests/test_migrate_status.sh` with 7 tests covering 4-digit, 3-digit, mixed prefixes, empty directories, non-migration files, and JSON output.

## [0.98.0] - 2026-08-03

### Added
- **`--init` flag** — Create starter schema with `rune --init` (equivalent to `rune init`). Works as a global flag alongside other options.
- **CLI integration** — `--init` added to `GLOBAL_FLAGS`, `ParsedArgs`, and `isKnownFlag` list.
- **Shell completions updated** — Bash, Fish, PowerShell include `--init` flag.
- **Help text updated** — `rune --help` shows `--init` option.

## [0.97.0] - 2026-08-03

### Added
- **Colored diff output** — `rune diff` now supports ANSI color output for terminal-friendly display. Added `--color` flag with three modes: `auto` (default, TTY detection), `always`, `never`. Colors: green for added, red for dropped, yellow for modified, blue+bold for table headers.
- **Diff summary statistics** — `rune diff` now prints a summary line after the diff: `"N tables changed (X added, Y dropped, Z modified)"`.
- **`color.zig` module** — New `src/color.zig` with ANSI escape code constants, `ColorMode` enum, and `writeColorized` helper.
- **Color unit tests** — 7 new tests in `color_test.zig` covering `ColorMode` variants and `ParsedArgs` defaults.
- **Color golden test** — New `tests/test_color.sh` with 5 tests verifying `--color always` produces ANSI codes, `--color never` produces plain text, and diff summary behavior.
- **Shell completions updated** — Bash, Fish, and PowerShell completions now include `--color` flag with `auto|always|never` values.

### Changed
- **`writeDiffTo` signature** — Added `use_color: bool` parameter to `diff/format/text.zig:writeDiffTo`. All callers updated.
- **`formatDiff` signature** — Added `color_mode: cli.ColorMode` and `io: std.Io` parameters. Pipeline diff handler threads color mode from CLI args.
- **`DiffConfig` struct** — Added `color: cli.ColorMode` field to `pipeline/diff.zig:DiffConfig`.

## [0.96.0] - 2026-08-03

### Fixed
- **Memory leak in reverse codegen** — `emitForeignKeys` in `reverse/codegen.zig` now properly frees memory allocated by `classifyFk`. Previously, each FK classification leaked its formatted text buffer.
- **Migration rollback semantics** — `generateRollback` now properly reverses all operations: `.create` tables become DROP TABLE, `.drop` tables become CREATE TABLE, field/index/FK diffs are inverted (add↔drop, modify swaps old/new), and view diffs are reversed.
- **Stale test counts** — Updated `test_coverage.sh` labels to match actual test counts: MySQL 85, PostgreSQL 86, Reverse Oracle 5, Reverse Db2 5, Reverse Confidence 3.

### Added
- **`PassAccess` conflict detection** — `semantic/pass_manager.zig` now validates that sequential passes don't have conflicting write-write access patterns. Catches at runtime when two passes both write tables without a dependency relationship.
- **Rollback unit tests** — 7 new tests in `migrate_test.zig` covering rollback of empty diffs, created tables, dropped tables, add/drop field reversal, add index reversal, and create view reversal.
- **Reverse codegen tests** — 6 new tests in `codegen_test.zig` covering schema header charset handling, table comments, multiple tables, FK shorthand form, and empty schema generation.

### Changed
- **Optimized reverse codegen template lookup** — `emitTables` now pre-builds a `table_index → template_index` lookup map for O(1) per-table template resolution, replacing the previous O(n*m) scan.
- **Re-exported `IndexDiff`/`FkDiff`** — `diff/engine.zig` now re-exports `IndexDiff`, `IndexAction`, `FkDiff`, and `FkAction` from `diff/types.zig` for consistent API access.

## [0.92.0] - 2026-08-03

### Fixed
- **`--output` long flag** — `--output` was listed as a known flag and in completions, but `parseArgs` only handled `-o`. The `--output` flag silently fell through as a positional argument. Now both `-o` and `--output` work correctly.

### Added
- **Subcommand help** — `rune diff --help`, `rune generate --help`, etc. now show subcommand-specific help instead of the general help. Added `hasHelpFlag` helper, `printSubcommandHelp` function, and updated `Command.help` to carry an optional subcommand name.
- **Early generator name validation** — `rune generate <invalid>` now produces a clear error message at the CLI level instead of failing deep in the pipeline.

### Changed
- **Deduplicated validate/check/stats parsers** — Extracted `parseSimpleInputArgs` helper to eliminate duplicated code across `parseValidateArgs`, `parseCheckArgs`, and `parseStatsArgs`.

## [0.87.0] - 2026-08-02

### Changed
- **Shared dialect type rendering helpers** — `common.emitVarchar`, `common.emitDecimal`, `common.emitEnumValues`, `common.emitEnumFixedType` replace 18+ per-dialect render functions across 6 backends.
- **Shared `emitAlterTableCommentShared`** — PG, Oracle, Db2 use a single `COMMENT ON TABLE` implementation.
- **Shared `emitIndexWithQuote`** — MSSQL, Oracle, Db2 share index rendering with configurable fulltext prefix.
- **Consolidated `emitAlterEngine`** — Oracle, MSSQL, Db2 reference `common.emitAlterEngineWarning` directly.

### Removed
- **Dead `canonicalSimple` dialect parameter** — Removed unused `dialect` parameter from `canonicalSimple`, `simpleEquiv`, and `typeInfoEquiv` in `diff/semantic.zig`. Updated all callers and tests.

## [0.86.0] - 2026-08-02

### Added
- **Extensible DialectTypeMap** — `types/reverse_map.zig` now provides `DIALECT_NAMES` comptime array and `getDialectType()` accessor. Adding a new SQL dialect requires only 3 changes (enum variant, struct field, switch case) instead of modifying every REVERSE_MAP entry.
- **Bench stage count comptime** — `bench.zig` now has a `STAGE_NAMES` comptime constant. Adding a new benchmark stage is a documented 4-step process.
- **Completions unit tests** — New `completions_test.zig` with 16 tests covering bash, zsh, fish, and powershell completion scripts plus the starter schema template.

### Fixed
- **Bench baseline format mismatch** — `test_bench.sh` now auto-migrates legacy `baseline.json` to per-dialect format and detects the `bench.zig` binary for per-stage timing.
- **Silent `std:` import fallback** — `import_resolver.zig` now emits a warning when an `std:` import path cannot be resolved in any search path, instead of silently falling back to the literal path.

### Changed
- **Comptime dialect iteration** — `reverse/map.zig` now uses `inline for` over `DIALECT_NAMES` instead of a hardcoded `or` chain for reverse lookup matching.
- Made `COMPLETIONS_BASH`, `COMPLETIONS_ZSH`, `COMPLETIONS_FISH`, `COMPLETIONS_POWERSHELL` public in `completions.zig` for test access.

## [0.85.0] - 2026-08-02

### Added
- **Property-based roundtrip tests** — New `tests/test_property_roundtrip.sh` generates random `.ss` schemas, compiles → reverses → recompiles, and verifies structural and semantic properties. Tests 30+ iterations across 3 dialects (MySQL, PostgreSQL, SQLite) with seed-reproducible output. Completes Phase 1 of ROADMAP.
- **Markdown diff format** — `rune diff --format markdown` produces clean markdown tables suitable for PR descriptions and documentation. Shows summary metrics, dropped tables, added tables with columns, and per-table modification details. New `diff/format/markdown.zig` with 3 unit tests.
- **Cross-dialect roundtrip testing** — Expanded `tests/test_roundtrip.sh` from 3 dialects (MySQL, PostgreSQL, SQLite) to 5 dialects (+Oracle, +Db2). Total roundtrip tests: 112 (was 68). MSSQL excluded due to known bracket-quoting bug in reverse pipeline.

### Fixed
- **OpenAPI golden test infrastructure** — `tests/test_openapi.sh` now uses `.json` extension for golden files (was `.sql`). Regenerated 3 golden files with correct OpenAPI 3.1 JSON output. Tests: 3/3 passing.
- **GraphQL golden test infrastructure** — `tests/test_graphql.sh` now uses `.graphql` extension for golden files (was `.sql`). Regenerated 4 golden files with correct GraphQL SDL output. Tests: 4/4 passing.
- **JSON Schema golden files** — Regenerated 3 golden files to match current generator output (corrected `required` array to include all non-nullable columns). Tests: 3/3 passing.

### Changed
- Updated CLI help text and fish completions to include `markdown` in `--format` options.
- Added `cli_test.zig` test for `--format markdown` parsing.

## [0.76.0] - 2026-08-02

### Added
- **Expanded Oracle reverse engineering tests** — Added 4 new golden tests to `tests/test_reverse_oracle.sh` covering TIMESTAMP WITH TIME ZONE multi-word types, GENERATED BY DEFAULT AS IDENTITY, inline block comments, and composite foreign keys. Total: 7 Oracle reverse tests (was 3).
- **Expanded Db2 reverse engineering tests** — Added 4 new golden tests to `tests/test_reverse_db2.sh` covering GENERATED ALWAYS AS IDENTITY with options, multi-word type handling (DOUBLE PRECISION, CHARACTER VARYING), BOOLEAN type, and composite indexes. Total: 7 Db2 reverse tests (was 3).
- **Parser unit tests for multi-word types** — Added 6 tests to `parser/sql_parser_test.zig` covering TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH LOCAL TIME ZONE, DOUBLE PRECISION, CHARACTER VARYING, CHAR FOR BIT DATA, and NUMERIC with precision.
- **Parser unit tests for Oracle identity options** — Added 4 tests covering GENERATED BY DEFAULT AS IDENTITY, GENERATED BY DEFAULT ON NULL AS IDENTITY, START WITH/INCREMENT BY options, and inline block comment extraction.
- **Parser unit tests for inline block comments** — Added 3 tests covering Oracle/Db2 style `/* comment */` inside column definitions, multi-line block comments, and block comments before NOT NULL.

### Changed
- **bench.zig refactoring** — Extracted `parseDialectArg`, `parseSchemaFile`, and `parseIterationCount` helper functions from `main()` for improved readability and testability. Each helper has dedicated unit tests.
- Updated `tests/expected/*.oracle.sql` golden files for Oracle dialect fixes from 0.75.2.

### Fixed
- **Oracle dialect fixes** (from 0.75.2) — Oracle golden files updated for corrected type rendering and identifier quoting.
- **SQL Parser identity options** (from 0.75.1) — Oracle `GENERATED BY DEFAULT ON NULL AS IDENTITY` and `START WITH`/`INCREMENT BY` options now correctly parsed.

## [0.75.2] - 2026-08-02

### Fixed
- **Oracle dialect golden file sync** — Updated 103 Oracle golden files to match corrected Oracle dialect output (type rendering, identifier quoting fixes).
- **Oracle dialect test fix** — Fixed `oracle_test.zig` assertion to match updated behavior.
- **parse_field.zig** — Added missing field handling for Oracle-style generated column expressions.

## [0.75.1] - 2026-08-02

### Added
- **SQL Parser: inline block comment parsing** — `sql_parser_create.zig` now handles `/* ... */` block comments inside column definitions (Oracle/Db2 style). Block comments are extracted as column comments when no other comment is present.
- **SQL Parser: Oracle identity options** — `GENERATED BY DEFAULT AS IDENTITY`, `GENERATED BY DEFAULT ON NULL AS IDENTITY`, and identity options (`START WITH`, `INCREMENT BY`, `MINVALUE`, `MAXVALUE`) are now parsed and skipped correctly.
- **SQL Parser: multi-word type handling** — `parseColumnType` now recognizes type continuation keywords (`WITH`, `TIME`, `ZONE`, `LOCAL`, `PRECISION`, `VARYING`, `FOR`, `BIT`, `DATA`) to correctly parse types like `TIMESTAMP WITH TIME ZONE`, `DOUBLE PRECISION`, `CHARACTER VARYING`, and `CHAR FOR BIT DATA`.
- **SQL Parser tests** — 219 new lines of unit tests covering the above parser enhancements.
- **Reverse map expansion** — 52 new entries in `types/reverse_map.zig` for Oracle and Db2 multi-word types and additional reverse mappings.
- **Reverse map tests** — 139 new lines in `reverse/map_test.zig` covering Oracle/Db2 reverse lookups and multi-word type matching.
- **Large schema test file** (`tests/000.ss`) — 519-line comprehensive test schema covering Chinese comments, template inheritance, complex FK relationships, and multi-level templates.

### Changed
- `reverse/map.zig` — Extended `reverseLookup` to handle Oracle and Db2 multi-word types via case-insensitive prefix matching.

## [0.75.0] - 2026-08-02

### Changed
- **Pipeline config structs** — Added `DiffConfig`, `MigrateConfig`, and `ReverseConfig` structs to replace 8-11 positional parameters in pipeline handlers. Follows the existing `CompileConfig` pattern from `pipeline/forward.zig`.
- **Unified diff handler** — Merged `handleDiff`, `handleDiffJson`, `handleDiffSarif` into a single `handleDiff(io, alloc, DiffConfig)` function that switches on `cfg.format`. Eliminated ~30 lines of duplicated prepare→trace→format→write logic.
- **Unified migrate handler** — Merged `handleMigrate` and `handleMigrateDiffJson` into a single `handleMigrate(io, alloc, MigrateConfig)` function.
- **Simplified reverse handler** — `handleReverse` now takes a `ReverseConfig` struct instead of 11 positional parameters.
- **Extracted `generateFromSchema` helper** — New `pipeline/forward.zig` function handles the full compile→generate→write pipeline. Used by both `rune generate` and `rune docs` in `main.zig`, eliminating duplicate dispatch logic.
- **Simplified main.zig dispatch** — `.diff`, `.migrate`, `.reverse`, `.docs`, `.generate` branches now construct config structs and delegate to pipeline handlers, reducing dispatch from ~80 lines to ~50 lines.

## [0.74.0] - 2026-08-02

### Added
- **Benchmark dialect parameterization** — `rune bench --dialect <d>` now benchmarks any SQL dialect (mysql, pg, sqlite, mssql, oracle, db2) instead of hardcoding MySQL. Baseline files are per-dialect (`bench/baseline-mysql.json`, `bench/baseline-pg.json`, etc.).
- **Dialect auto-detection for all 6 dialects** — `reverse/dialect_detect.zig` now detects MSSQL, Oracle, and Db2 DDL patterns in addition to MySQL, PostgreSQL, and SQLite. Previously, MSSQL/Oracle/Db2 DDL fell through to MySQL default.
- **Benchmark unit tests** (`bench_test.zig`) — 12 tests covering `parseDialect` for all 6 dialects plus aliases and error cases.
- **Dialect detection tests expanded** — 7 new tests in `dialect_detect_test.zig` covering MSSQL (`IDENTITY(1,1)`, `NVARCHAR`, `[dbo]`), Oracle (`VARCHAR2`, `NUMBER`, `SYSDATE`, `SEQUENCE`), and Db2 (`GENERATED ALWAYS AS IDENTITY`, `DECFLOAT`) patterns.

### Fixed
- **CLI help text** — Added missing `db2` to the `-d` flag example in usage output.

### Changed
- Benchmark baseline files renamed from `baseline.json` to `baseline-{dialect}.json` (backward-compatible migration applied).

## [0.73.0] - 2026-08-02

### Added
- **Dialect-aware reverse engineering for Oracle and Db2** — `reverseLookup` in `reverse/map.zig` now matches against Oracle and Db2 type columns in `REVERSE_MAP`, enabling accurate reverse engineering of Oracle DDL (`VARCHAR2(N)`, `NUMBER(P,S)`, `CLOB`, `BLOB`, etc.) and Db2 DDL (`VARCHAR(N)`, `DECIMAL(P,S)`, `INTEGER`, `SMALLINT`, `BIGINT`, etc.) to `.ss` format.
- **Case-insensitive parameterized type matching** — Added `matchPrefix` helper for case-insensitive prefix matching in `reverseLookup`. Oracle and Db2 DDL uses uppercase type names (`VARCHAR2(100)`, `NUMBER(10)`, `DECIMAL(10,2)`) which now correctly match against parameterized type patterns.
- **Oracle parameterized type handlers** — Added reverse mapping for `VARCHAR2(N)` → `sN`, `NUMBER(P,S)` → `P,S`, and `NUMBER(P)` → `N` (with case-insensitive matching).
- **3 Oracle reverse golden tests** (`tests/test_reverse_oracle.sh`) — basic types, indexes, and full type coverage.
- **3 Db2 reverse golden tests** (`tests/test_reverse_db2.sh`) — basic types, indexes, and full type coverage.

### Changed
- `test_coverage.sh` now runs 20 suites (was 18) — added Reverse Oracle and Reverse Db2.

## [0.64.0] - 2026-08-01

### Fixed
- **TypeORM FK emission** — TypeORM generator now correctly emits `@ManyToOne` + `@JoinColumn` decorators for foreign key columns. Previously, FK columns were silently skipped with no relation output.
- **Knex varchar(0)** — Knex generator now defaults to 255 when varchar length is 0, matching the behavior of all other generators (TypeORM, SQLAlchemy, Docs). Previously emitted `string('name', 0)` which is invalid in Knex.
- **SQLAlchemy multi-index** — SQLAlchemy generator now emits a single `__table_args__` tuple containing all table-level constraints (composite indexes, unique constraints, single-column indexes). Previously emitted one `__table_args__` assignment per index, with only the last surviving.
- **Partial compilation warning** — `rune compile` now emits a warning when the schema has parse errors but valid tables can still produce SQL output. Shows the count of skipped tables.

### Added
- **MSSQL unit tests** — Added `dialect/mssql_test.zig` with 9 tests covering type rendering (12 SQL types), quoteChar, quoteIdent, emitPrimaryKey, emitTimestampModifier, emitCreateView, emitEnumTypeCheck, capability flags, and generated columns. MSSQL now has test coverage matching MySQL/PG/SQLite.
- **Partial compilation** — `PipelineResult` now includes `partial: bool` and `skipped_tables: u32` fields. The pipeline continues with semantic analysis and codegen when parse errors exist, producing SQL for valid tables only.

## [0.63.0] - 2026-08-01

### Added
- **Synchronized multi-error recovery** — Parser records all syntax errors in a single pass via `DiagnosticCollector` and returns a partial AST with `error_count` field. Users see all parse errors at once instead of stopping at the first one.
- **`Ast.error_count` field** — New field on `types/ast.zig` Ast struct tracks the number of parse errors recorded during parsing. When > 0, the AST is partial (some tables/templates may be missing).
- **`tokenizeAndParseLenient` function** — New function in `pipeline/import_resolver.zig` that returns the parsed tree without printing errors, for scenarios where error printing should be deferred.

### Fixed
- VERSION file sync (was 0.61.0, now matches version.zig at 0.63.0).

## [0.60.0] - 2026-08-01

### Added
- **OpenAPI 3.1 generator** (`rune generate openapi`) — generates OpenAPI 3.1 specification from `.ss` files. Produces `components/schemas` with table object definitions, property type mappings (via JSON Schema), required arrays, FK `$ref` references, enum values, CHECK constraint metadata, and default values. Views included as read-only schemas.
- 8 new unit tests for OpenAPI generator (`generators/openapi_test.zig`).
- 3 new golden tests (`test_openapi.sh`) covering basic schemas, FK references, and template inheritance.

### Changed
- Generator registry expanded from 8 to 9 generators.
- All new generator registered in `REGISTRY` — no `main.zig` changes needed.

## [0.53.0] - 2026-07-30

### Changed
- **Shared default value formatting** — extracted duplicated `writeDefault` logic from 4 ORM generators (drizzle, knex, typeorm, sqlalchemy) into `generators/common.zig`. Introduced `DefaultFormatter` struct with language-specific callback function pointers (`boolTrue`, `boolFalse`, `nullValue`, `now`, `formatString`) and shared `writeFormattedDefault` function. Each generator now provides thin config wrappers instead of full parsing implementations.

### Added
- 22 new unit tests:
  - `parser/parse_recovery_test.zig` (16 tests) — error recording, block boundary detection, `findNextBlockBoundary`, `locFromLine`
  - `pipeline/import_resolver_test.zig` (6 tests) — line splitting, base directory computation, slice concatenation, `ImportContext` defaults

### Fixed
- Replaced unsafe `@intFromPtr` pointer arithmetic in `parse_field.zig:356-357` with safe `std.mem.indexOf` for generated column expression extraction

## [0.52.0] - 2026-07-30

### Changed
- **Migration engine refactoring** — unified forward/rollback codepaths in `diff/migrate.zig`. Eliminated ~180 lines of duplicated emit functions by introducing a shared `Direction` enum and unified `emitFieldDiffs`, `emitIndexDiffs`, `emitFkDiffs`, `emitMetadataDiffs` functions that handle both directions via field selection.
- **Consolidated whitespace helpers** — merged `skipWhitespaceAndComments` and `skipWhitespaceAndCommentsNoSemicolon` into a single function in `sql_parser_helpers.zig`. The "NoSemicolon" variant was identical in behavior.

### Fixed
- Replaced 3 unsafe `unreachable` statements in runtime code with proper error handling:
  - `parse_index.zig` — `.primary_key => unreachable` → `return error.UnexpectedPrimaryKey` (2 occurrences)
  - `reverse/codegen.zig` — `.primary_key => unreachable` → `else => {}` (already guarded by `continue`)

## [0.51.0] - 2026-07-30

### Added
- **TypeORM generator** (`rune generate typeorm`) — generates TypeORM entity classes from `.ss` files. TypeScript decorators: `@Entity`, `@Column`, `@PrimaryGeneratedColumn`, `@ManyToOne`, `@JoinColumn`, `@Index`. Supports enum types via `@Column({ type: 'enum', enum: [...] })`. Nullable, default values, and composite index support.
- **SQLAlchemy generator** (`rune generate sqlalchemy`) — generates SQLAlchemy ORM models from `.ss` files. Python declarative base with `Column()`, `ForeignKey`, `Index`, `UniqueConstraint`. Type mapping: int→Integer, varchar→String(N), text→Text, boolean→Boolean, datetime→DateTime, decimal→Numeric(precision, scale), enum→Enum.
- **Knex.js generator** (`rune generate knex`) — generates Knex.js migration files from `.ss` files. `exports.up`/`exports.down` pattern with `createTable`, `table.increments`, `table.foreign().references()`, `table.index()`. Supports single and composite indexes/foreign keys.
- 24 new unit tests (8 per generator).
- `rune generate --list` now shows 8 generators.

### Changed
- Generator registry expanded from 5 to 8 generators.
- All new generators registered in `REGISTRY` — no `main.zig` changes needed.

## [0.49.0] - 2026-07-30

### Added
- **Drizzle ORM generator** (`rune generate drizzle`) — generates Drizzle ORM TypeScript schema from `.ss` files. Supports all 3 dialects (`pgTable`, `mysqlTable`, `sqliteTable`). Includes column modifiers (`.primaryKey()`, `.autoincrement()`, `.notNull()`, `.default()`, `.unique()`), FK `.references()`, `index()`/`uniqueIndex()`, and enum types (`pgEnum` for PG, const arrays for MySQL/SQLite).
- **Enhanced JSON Schema generator** — added `$defs` section with reusable table schemas, `$ref` for FK column references, proper `required` arrays per table, `additionalProperties: false`, and table/column descriptions.
- `rune generate --list` now shows 5 generators.
- 14 new unit tests (8 Drizzle + 6 JSON Schema).

### Changed
- Updated 244 golden test files from version 0.48.0 to 0.49.0.
- Fixed pre-existing golden test mismatches (decimal spacing, column names, trailing commas in PG migration output).

## [0.48.0] - 2026-07-29

### Added
- **SQL DDL generator** (`rune generate sql-ddl`) — wraps the existing codegen engine to output SQL DDL as a standalone generator. Supports all 3 dialects (MySQL, PostgreSQL, SQLite).
- **Prisma schema generator** (`rune generate prisma`) — generates Prisma schema from `.ss` files. Maps SS types to Prisma types, includes `@id`, `@default(autoincrement())`, `@unique`, `@@map`, and nullable `?` suffixes.
- **Markdown docs generator** (`rune generate docs`) — generates structured Markdown documentation from `.ss` files. Includes table overview, per-table column details, and index listings.
- `rune generate --list` now shows 4 generators (was 1).

### Changed
- **main.zig error dispatch** — extracted `cliArgErrorMessage` helper for CLI argument errors, replacing repetitive switch statement with table-driven error messages.
- Updated 244 golden test files from version 0.46.0 to 0.48.0.

## [0.47.0] - 2026-07-29

### Changed
- **Module splits** — extracted `pipeline/import_resolver.zig` from `forward.zig` (import resolution logic) and `diff/migrate_helpers.zig` from `migrate.zig` (shared `emitSingleTable` helper). Reduces `forward.zig` from 548 to ~300 lines and `migrate.zig` from 652 to ~600 lines.
- **Moved `emitCheckExpr`** — relocated dialect-independent CHECK expression rendering from `dialect/dialect.zig` to `codegen/codegen.zig` where it belongs.
- **Auto-computed parallel groups** — replaced hardcoded `getParallelGroups()` in `pass_manager.zig` with a greedy graph-coloring algorithm that computes groups from the dependency graph. No manual maintenance needed when passes are reordered or added.

### Added
- **`grammar.ebnf`** — formal EBNF grammar specification for the `.ss` schema language.
- **`schema.md`** — complete language reference with syntax, constructs, and examples.
- **`type.md`** — type system reference documenting all 17 SS symbols, parameterized types, custom types, and dialect-specific rendering.
- Fixed README.md testing section — removed references to non-existent golden test shell scripts, documented actual `zig build test` command.
- Updated ARCHITECTURE.md with new module extractions.

## [0.46.0] - 2026-07-29

### Changed
- **CLI parseArgs refactor** — split monolithic 170-line `parseArgs` into subcommand-specific parsers (`parseDiffArgs`, `parseMigrateArgs`, `parseReverseArgs`, `parseGenerateArgs`, `parseSimpleSubcommand`). Extracted `GlobalFlags` struct for shared flag state.
- **Safe optional unwraps** — replaced 3 unsafe `result.resolved.?` panics in `pipeline/forward.zig` with explicit `orelse return error.SemanticError`, preventing undefined behavior when semantic analysis is skipped.
- **validate_indexes decomposition** — extracted `checkDuplicateNames`, `checkSemanticDuplicates`, `checkColumnRefs` helper functions from monolithic `run()`. Same behavior, improved readability.
- Updated 244 golden test files from version 0.45.0 to 0.46.0.

## [0.45.0] - 2026-07-29

### Added
- **DialectCapability system** — `DialectCapability` struct with 12 feature flags (`auto_increment`, `unsigned`, `create_database`, `enum_type`, `inline_comments`, `standalone_comments`, `schemas`, `sequences`, `tablespace`, `batch_separators`, `generated_columns`, `alter_drop_column`). Each dialect backend declares its capabilities, enabling callers to check dialect features without switch statements. Ready for Phase 2 enterprise dialects (Oracle, MSSQL, Db2).
- **CompileConfig struct** — replaced 13-parameter `handleCompileRequest` with a single `CompileConfig` struct. All parameters have named defaults; callers specify only what they need.
- **Generator API dialect awareness** — `Generator.generate` signature now includes `dialect: Dialect` parameter, enabling dialect-specific code generators (Prisma, OpenAPI, etc.).
- **CLI unknown-flag detection** — unrecognized `--` flags now produce `error.UnknownFlag` with the flag name in the error message, instead of silently treating them as file paths.
- **io.zig unit tests** — 5 new tests for I/O helper logic (stdin detection, output path routing).

### Changed
- **Allocator consistency** — replaced `std.heap.page_allocator` with arena allocator in `edit_distance.zig` (stack-allocated DP arrays), `diagnostic.zig` (JSON formatting), and `pass_manager.zig` (dependency validation). Reduces memory tracking noise in leak detection.
- Refactored `pass_manager.validateDependencyOrder` and `transitiveDependsOn` to accept explicit `Allocator` parameter.
- Updated `edit_distance.distance` to use stack-allocated `[256]usize` arrays instead of heap-allocated `ArrayList`, eliminating per-call heap allocations for Levenshtein computation.
- Updated 247 golden test files from version 0.44.0 to 0.45.0.

### Dialect Capabilities
| Capability | MySQL | PostgreSQL | SQLite |
|-----------|-------|-----------|--------|
| auto_increment | ✓ | | |
| unsigned | ✓ | | |
| create_database | ✓ | ✓ | |
| enum_type | ✓ | | |
| inline_comments | ✓ | | |
| standalone_comments | | ✓ | |
| schemas | | ✓ | |
| sequences | | ✓ | |
| tablespace | ✓ | | |
| generated_columns | | ✓ | ✓ |
| alter_drop_column | ✓ | ✓ | |

## [0.44.0] - 2026-07-29

### Fixed
- Fixed `reverseLookup` ignoring `confidence_base` from REVERSE_MAP — `ReverseResult.score` now correctly propagates the confidence base score (was always defaulting to 100)
- Fixed `classifyCheck` misclassifying `[]` brackets with comparison operators — expressions like `[price > 0]` now correctly return `.comparison` instead of `.range`
- Fixed 5 unit test expectations: tokenizer fused type modifier (2→2 tokens), enum type (5 tokens), comment stops at -- (2 tokens), inline FK (4 tokens), indexes standalone/inline MySQL→PG backend, parse_check single value `.in_list`

## [0.43.0] - 2026-07-29

### Added
- Generator registry (`generator.zig`) — pluggable `Generator` struct with `REGISTRY` array, `get(name)` lookup, and `listAll()` for CLI output. Adding a new generator requires only adding an entry to `REGISTRY`.
- Parallel golden test runner (`tests/test_parallel.sh`) — runs 12 test suites concurrently for faster CI. Uses `tests/lib_parallel.sh` helper library.

### Fixed
- Fixed memory leak in `semantic/pass_manager.zig:detectConflicts()` — now accepts `Allocator` parameter instead of using `std.heap.page_allocator` directly. Callers are responsible for freeing the returned slice.
- Fixed memory leak in `semantic/pass_manager.zig:transitiveDependsOn()` — added `defer` cleanup for `BufSet` and `ArrayList` allocated with `page_allocator`.

### Changed
- Refactored `main.zig` generate dispatch to use `generator.get(name)` instead of hardcoded `if/else` on generator name string.
- Updated 244 golden test files from version 0.42.0 to 0.43.0.

### Testing
- Updated `pass_manager_test.zig` — `detectConflicts` test now uses `testing.allocator` with proper `defer free`.

## [0.42.0] - 2026-07-29

### Fixed
- Fixed buffer overflow risk in `reverse/map.zig` — added bounds checking for decimal/numeric parameterized type patterns to prevent memory corruption with oversized type parameters

### Added
- `rune generate` subcommand — foundation for ORM/API schema output (Phase 3)
- `rune generate json-schema` — generate JSON Schema (draft-07) from .ss files
- `rune generate --list` — show available generators

### Changed
- Extracted `hasChanges()` method on `SchemaDiff` — eliminates 3x duplicated check blocks in `pipeline/diff.zig`

### Testing
- Added 3 unit tests for `diff/types_test.zig` (`hasChanges()` method)
- Added 2 unit tests for `reverse/map_test.zig` (decimal/numeric overflow guard)
- Updated 244 golden test files from version 0.38.0 to 0.42.0

## [0.40.0] - 2026-07-29

### Fixed
- Fixed memory leaks in `diff/indexes.zig` — two `StringHashMap`s (`old_by_name`, `new_by_name`) created but never freed in `diffIndexes()`
- Fixed memory leaks in `diff/engine.zig` — four `StringHashMap`s (`old_map`, `new_map`, `old_view_map`, `new_view_map`) created but never freed in `diff()`
- Fixed memory leaks in `diff/fields.zig` — two `StringHashMap`s (`old_fmap`, `new_fmap`) and three intermediate `ArrayList`s (`diffs`, `dropped_names`, `added_fields`) freed properly
- Fixed memory leaks in `diff/fks.zig` — two `ArrayList.toOwnedSlice(alloc)` calls replaced with safe `dupe + deinit` pattern
- Fixed memory leaks in `parser/tokenizer.zig` — `raw_tokens` ArrayList and `tokens` ArrayList buffer freed in `tokenizeLine()`
- Fixed redundant allocations in 8 production files — replaced `aw.toArrayList().toOwnedSlice(alloc)` pattern with `aw.toOwnedSlice()` (eliminates double-allocation)
- Fixed `validate` vs `check` CLI behavior — `rune validate` now always succeeds (exit 0) even with errors; `rune check` exits 1 on errors (CI gate)
- Fixed error message for unknown `--format` to include `sarif` option

### Changed
- `diff/engine.zig`: `diff()` now uses `alloc.dupe() + clearAndFree()` pattern instead of `ArrayList.toOwnedSlice(alloc)` to prevent ArrayList buffer leaks
- `diff/indexes.zig`: `diffIndexes()` and `createAllIndexDiffs()` use same safe pattern
- `diff/fields.zig`: `diffFields()`, `createAllFieldDiffs()`, and `detectRenames()` use same safe pattern
- `diff/fks.zig`: `diffFks()` and `createAllFkDiffs()` use same safe pattern

### Testing
- Fixed memory leaks in `diff/migrate_test.zig` — all 6 tests now properly free allocated `dropped` slices and returned SQL strings
- Fixed memory leaks in `diff/format/text_test.zig`, `json_test.zig`, `sarif_test.zig` — `dropped` slices properly freed
- Fixed memory leak in `json_schema_test.zig` — `vals` slice properly freed
- Fixed pre-existing test bug in `migrate_test.zig` — migration header assertion updated to match actual output format
- Fixed 4 diff_test failures by switching to arena allocators
- Memory leaks reduced from 606 to 533 (73 fewer)

## [0.38.0] - 2026-07-28

### Fixed
- Fixed broken `ast_visitor_test.zig` — test defined no-op callbacks but expected counters to increment, causing 24 test failures + 3 crashes + 592 memory leaks
- Fixed memory safety issue in `diff/fks.zig:adjustFkForRenames` — replaced fixed-size `[8]` stack buffers with allocator-based dynamic arrays to handle FKs with >8 fields
- Fixed pre-existing memory leak in `diff/fks.zig:diffFks` — `old_matched` and `new_matched` ArrayLists were never freed
- Fixed PG `emitAlterAddIndex` — regular indexes now emit standalone `CREATE INDEX` statement instead of a comment, preventing silent migration failures
- Fixed FK constraint name separator in MySQL and PostgreSQL `DROP FOREIGN KEY` — field names now use `_` separator (e.g., `fk_user_id_org_id` instead of `fk_user_idorg_id`)

## [0.37.0] - 2026-07-28

### Fixed
- Fixed broken colocated test compilation (72 errors) from v0.36.1 test extraction
- Fixed API mismatches across 30+ test files (function signatures, struct fields, Zig 0.16 API changes)

### Added
- `--json-errors` flag for machine-readable diagnostic output (CI/CD integration)
- `rune check` standalone subcommand for schema validation

## [0.36.0] - 2026-07-28

### Architecture
- **Comptime RenderEntry validation**: Added compile-time check in `renderFromTable()` that validates render table length matches SqlType enum variant count. Catches silent mismatches when adding new SqlType variants.
- **TypedAst ss_symbol cleanup**: Renamed `TypedColumn.sym_type` → `ss_symbol` with documentation clarifying it's for SQLite roundtrip fidelity only. Reduces cognitive burden on the core IR type.
- **Diff FK rename detection**: `diffFks()` now accepts field diffs and performs rename-aware matching (Pass 1.5). When a column is renamed and an FK references it, the FK diff produces `modify` instead of `drop + add`. Added `adjustFkForRenames()` helper and 3 new unit tests.

### Code Quality
- **Shared test helpers**: Extracted `makeTestColumn()` from 5 test files into `semantic/test_helpers.zig`. Updated `codegen/columns.zig`, `codegen/indexes_test.zig`, `codegen/codegen_test.zig`, `codegen_test.zig`, `json_schema.zig` to use the shared version.
- **Test extraction**: Moved ~310 inline unit tests from 35 production files into 30 new colocated `*_test.zig` files. Production files are now pure logic; only `diff/fields.zig` and `semantic/pass/*.zig` retain inline tests. Made `canonicalSimple`, `simpleEquiv`, `classifyModifiers`, `buildSymType`, `classifyLine` pub for test access.
- **Dead code cleanup**: Removed 6 unused imports, 9 unused re-exports from `diff/engine.zig`, and 2 dead root test files (`diff_test.zig`, `codegen_test.zig`).

### Documentation
- **`rune/README.md`**: New contributor README with project overview, quick start, commands, CLI flags reference, testing instructions, project structure, and contributing guide.
- **ARCHITECTURE.md**: Fixed roundtrip test count (20 → 26), updated total (~480+ → ~486+).
- **CLAUDE.md**: Fixed roundtrip test count (20 → 26).

## [0.35.0] - 2026-07-28

### Fixed
- Re-enabled colocated test files that were disabled since v0.28.0 SqlType refactor
- Fixed 9 compilation errors across colocated test files: string→SqlType type mismatches, missing struct fields, deprecated `getWritten()` API, wrong namespace references
- Fixed test memory leaks in colocated tests using arena allocators
- Fixed golden file naming inconsistency (view golden files: dash → dot convention)

### Added
- `tests.zig` test module index for colocated test files
- Second test step in `build.zig` for colocated test compilation

### Changed
- Updated `rune/ARCHITECTURE.md` testing table with correct test counts

## [0.33.0] - 2026-07-27

### Architecture
- **Extract shared reverse mapping data**: Moved `REVERSE_MAP` data from `reverse/map_data.zig` → `types/reverse_map.zig` (canonical location). `reverse/map_data.zig` now re-exports for backward compatibility.
- **Colocate test files with modules**: Moved `diff_test.zig`, `fields_test.zig`, `codegen_test.zig` to their logical module directories (`diff/`, `codegen/`).
- **Reverse map unit tests**: Added 25 new tests to `reverse/map.zig`: round-trip tests, confidence score range validation, data integrity checks.

## [0.34.0] - 2026-07-27

### Architecture
- **Diff format module split**: Refactored monolithic `diff/format.zig` (518 lines) into 4 files: `format.zig` (re-export, 36 lines), `format/text.zig` (text, 260 lines), `format/json.zig` (JSON, 130 lines), `format/sarif.zig` (SARIF, 180 lines). Each format is now independently maintainable.
- **SARIF version from source**: `format/sarif.zig` now reads `version.VERSION` from `version.zig` instead of hardcoding `"0.30.0"`.

### Testing
- **Golden file version sync**: Updated 247 golden test files from version 0.32.0 to 0.34.0.

## [0.32.0] - 2026-07-27

### Architecture
- **Implicit global state eliminated**: Removed `threadlocal global_allocator` / `global_backend` from `codegen/codegen.zig`. All dialect backend and allocator access now goes through `Codegen` struct fields (`self.alloc`, `self.backend`).
- **Type resolution clean separation**: Verified `SqlType.fromTypeInfo` only maps `TypeInfo` → `SqlType` without string parsing. Parameterized type parsing correctly lives in `parser/parse_field.zig` (forward) and `reverse/map.zig` (reverse).

### Testing
- All test suites pass: MySQL 86/86, PostgreSQL 84/84, SQLite 25/25, Diff 12/12, Migration 34/34.

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
