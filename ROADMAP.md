# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.197.0 (2026-08-10) — 53,600+ lines production Zig, 1,482+ tests, 33 test suites.

---

## Legend

- [x] Done — shipped in a release
- [ ] Planned — not yet started
- [~] In progress — partial implementation exists
- Priority is top-down within each section; sections overlap in practice
- Version numbers are approximate — shipped when ready, not by deadline

---

## Completed Work

Phases 1–4 are fully complete. Phase 5 is nearly complete. Phase 6 is the current focus.

### Phase 1: Core Solidification ✅

Polished the parser, semantic analysis, and testing infrastructure. Shipped v0.38–v0.81.

Multi-error recovery, partial schema compilation, cycle detection, FK validation, template warnings, duplicate column detection, Levenshtein suggestions, fuzz testing, golden test parallelization, and property-based roundtrip tests.

### Phase 2: Extended Dialect Support ✅

Added all 6 SQL dialect backends. Shipped v0.48–v0.76.

MySQL, PostgreSQL, SQLite, MSSQL, Oracle, IBM Db2. DialectBackend vtable (33 function pointers), 12 capability flags, shared helpers, dialect-specific test suites (470+ golden tests), dialect-aware reverse engineering, dialect auto-detection, and shared reverse mapping data (52+ entries).

### Phase 3: ORM & API Schema Output ✅

Bridged database schemas to application code. Shipped v0.48–v0.88.

Prisma, Drizzle, TypeORM, SQLAlchemy, Knex generators. OpenAPI 3.1, GraphQL SDL, JSON Schema, symbol-index output. Pluggable generator registry, shared test helpers, ORM default formatter.

### Phase 4: Incremental & Live Workflows ✅

Moved from batch compilation to interactive usage. Shipped v0.93–v0.139.

Incremental migration, file naming, dependency graph, `rune migrate status`, `rune watch`, live database diff, schema drift detection, GitHub Action, GitLab CI template, pre-commit hook generator.

### Phase 5: Developer Experience ✅ (LSP)

Built the language server and editor fundamentals. Shipped v0.144–v0.146.

LSP server with JSON-RPC 2.0, document sync, real-time diagnostics, completion, hover, go-to-definition, document symbols, code actions, and document formatting. WASM cross-compilation, Windows native builds, ARM64 CI.

---

## Phase 6: Ecosystem & Community 🔲

Build the community and ecosystem around Rune. **Not started.**

### Distribution

- [x] Package managers — `brew install rune`, `scoop install rune`, `apt`/`yum` (v0.150.0)
- [x] npm package — `npx rune schema.ss` (v0.191.0)
- [x] Docker image — `ghcr.io/rune-lang/rune:latest` (v0.150.0)
- [x] Zig package manager — `build.zig.zon` for dependency consumption (v0.195.0)

### Documentation

- [ ] Interactive tutorial — web-based walkthrough with live examples
- [x] Migration guide — from SQL DDL, Prisma, Knex to Rune `.ss` (v0.150.0)
- [x] Cookbook — common patterns (multi-tenant, soft delete, audit trail) (v0.184.0)
- [ ] Video walkthroughs — schema design, migration, CI/CD integration

### Community

- [ ] RFC process — formal proposal mechanism for language changes
- [ ] Schema registry — shared template library
- [ ] Playground sharing — share `.ss` snippets via URL

---

## Phase 7: Editor Extensions 🔲

Extend the LSP foundation into full editor experiences.

### VS Code Extension

- [x] Syntax highlighting — TextMate grammar for `.ss` files (v0.151.0)
- [x] Completion — wire LSP completion into VS Code's IntelliSense (v0.152.0)
- [x] Diagnostics — squiggly lines for errors and warnings (v0.152.0)
- [x] Commands — `Rune: Validate`, `Rune: Generate`, `Rune: Init` (v0.151.0)
- [x] Rename — rename table/column with FK reference updates (v0.153.0)
- [x] Enhanced completion — context-aware FK targets, template refs, prefix filtering (v0.153.0)
- [x] Rich hover — SQL DDL preview, FK relationship details, view SQL (v0.153.0)

### Neovim Plugin

- [x] LSP-based setup — `lspconfig` integration (v0.191.0)
- [ ] Treesitter grammar — `.ss` file highlighting
- [x] Keybindings — `gd` (go-to-def), `K` (hover), `<leader>rn` (generate) (v0.191.0)

### JetBrains IDE Plugin

- [ ] IntelliJ-based schema editor — code completion, inspections
- [ ] Integration with LSP server — reuse existing `rune lsp` binary

---

## Phase 8: Language Evolution 🔲

Extend the `.ss` language and pipeline for new use cases.

### Generator Plugin System

- [ ] User-defined generators via Zig plugins or WASM modules
- [ ] Template overrides — `.rune-template` files for customizing generator output
- [ ] Generator marketplace — community-contributed generators

### Advanced Schema Features

- [ ] Composite types — reusable field groupings beyond templates
- [ ] Schema versioning — `@version` directive for forward/backward compatibility
- [x] Conditional schemas — `@if(dialect=pg)` blocks for dialect-specific fields (v0.191.0)
- [ ] Schema documentation — `@doc` directive for inline documentation generation

### Pipeline Extensions

- [ ] SQL formatting — `rune format --dialect pg` for dialect-aware SQL formatting
- [x] Schema visualization — generate ER diagrams from `.ss` files (v0.191.0, Mermaid in docs generator)
- [ ] Live collaboration — multi-user schema editing via LSP extensions

---

## Architecture Targets

Ongoing improvements pursued alongside feature work.

### Performance

- [x] Streaming compilation — output SQL as soon as each table is resolved (v0.102.0)
- [x] Parallel table compilation — compile independent tables concurrently (v0.120.0)
- [x] Memory-mapped file I/O — for large schema files (>10MB) (v0.123.0)
- [x] Benchmark CI gate — enforce no regressions beyond 10% (v0.82.0)
- [x] Benchmark dialect parameterization — `rune bench --dialect <d>` supports all 6 dialects (v0.74.0)
- [x] Zero-allocation codegen path — reuse buffers across compilations (BufferPool extended to parallel codegen, v0.184.0)
- [ ] Incremental compilation — recompile only changed tables

### Code Quality

- [x] Remove all `catch unreachable` in production code (v0.39.0–v0.105.0)
- [x] Remove all unsafe `@intCast`/`@enumFromInt` in production code (v0.80.0)
- [x] Named constants for magic numbers (v0.80.0)
- [x] Eliminate `std.process.exit` in library code (v0.80.0–v0.103.0)
- [x] Formalize IR versioning — schema for forward/backward compatibility (v0.108.0)
- [x] Memory leak audit — reduce remaining leaks toward zero (v0.123.0)
- [x] Fuzz testing expansion — longer runs, more seed variety (v0.123.0)
- [x] Production error recovery — graceful handling of OOM, file system errors (v0.184.0)
- [x] Enhanced test coverage for under-tested modules (v0.190.0)
- [x] Additional test coverage: cli/parse, lsp/protocol, architecture cleanup (v0.197.0)

### Platform

- [x] Cross-compile to WASM — enable browser and Deno usage (v0.143.0)
- [x] Windows native builds — test and document MSVC/MinGW paths (v0.143.0)
- [x] ARM64 CI — test on Apple Silicon and ARM Linux (v0.143.0)
- [ ] FreeBSD CI — test on FreeBSD for server deployments
- [ ] CI pipeline optimization — reduce test suite runtime below 5 minutes

---

## Technical Debt

Tracked items that should be addressed but don't fit neatly into a phase.

- [x] Remove generator duplication — `openapi.zig` and `json_schema.zig` share ~200 lines of schema property logic (v0.147.0)
- [x] Consolidate `cli/types.zig` — 16+ flags scattered across parse modules could use a FlagRegistry pattern (v0.149.0)
- [x] Improve reverse engineering confidence scores — currently binary (high/low), could be granular (v0.149.0)
- [x] Standardize error message format — some use "error:", others use "Error:", others have no prefix (v0.147.0)
- [x] Expand golden test automation — currently 25 suites, some generators lack golden tests (typeorm, sqlalchemy, knex) (v0.147.0)
- [x] Table-driven LSP method dispatch — replace if-else chain with dispatch table (v0.186.0)
- [x] Data-driven lint rule dispatch — replace repetitive guard-then-call blocks (v0.186.0)
- [x] Standardize error output — unified all modules to use diagnostic/format.zig (v0.187.0)

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1: Core Solidification | ✅ Complete | 9/9 | 0 |
| 2: Extended Dialect Support | ✅ Complete | 14/14 | 0 |
| 3: ORM & API Schema Output | ✅ Complete | 13/13 | 0 |
| 4: Incremental & Live Workflows | ✅ Complete | 10/10 | 0 |
| 5: Developer Experience | ✅ Complete | 13/13 | 0 |
| 6: Ecosystem & Community | 🔲 In Progress | 3/8 | 5 |
| 7: Editor Extensions | 🔲 In Progress | 9/10 | 1 |
| 8: Language Evolution | 🔲 In Progress | 2/10 | 8 |
| Architecture Targets | ✅ Complete | 15/15 | 0 |
| Technical Debt | ✅ Complete | 8/8 | 0 |
| **Total** | | **96/105** | **9** |

---

## Roadmap by Quarter

### 2026 Q3 (Jul–Sep)

Focus: Distribution, documentation, and editor extensions.

**Distribution** — Get Rune into package managers (brew, scoop, apt). Create Docker image. Publish npm package.

**Documentation** — Write interactive tutorial. Create migration guide from Prisma/SQL. Record video walkthroughs.

**VS Code Extension** — Ship syntax highlighting and LSP integration for `.ss` files.

### 2026 Q4 (Oct–Dec)

Focus: Language evolution, advanced features, and community.

**Generator Plugin System** — Enable user-defined generators via WASM modules.

**Advanced Schema Features** — Composite types, schema versioning, conditional schemas.

**Community** — Establish RFC process. Launch schema registry. Build playground for sharing snippets.

**Neovim + JetBrains** — Ship LSP-based editor plugins for non-VS Code users.

### 2027 Q1 (Jan–Mar)

Focus: Performance, platform coverage, and ecosystem maturity.

**Zero-Allocation Codegen** — Reuse buffers across compilations for large schemas.

**Incremental Compilation** — Recompile only changed tables.

**Platform Expansion** — FreeBSD CI, cross-compilation improvements.

**Schema Visualization** — Generate ER diagrams from `.ss` files.

---

## Release History

For detailed per-version release notes, see [CHANGELOG.md](CHANGELOG.md).

### Recent Releases

- **v0.197.0** — Test coverage & architecture cleanup: added 49 new tests for cli/parse (argument parsing, flag detection, suggestions) and lsp/protocol (JSON-RPC message writing), consolidated getInputPath/getInputPath2 into single getInputPaths function, registered new test files in tests.zig
- **v0.196.0** — Architecture refactoring & quality: extracted docs/format command handlers from main.zig dispatch to pipeline/handlers.zig (reduced dispatch function by 40 lines), fixed parser BlockState memory leak (parents_buf not freed in reset), optimized stripEngineTokens to avoid allocation when no engine token present, eliminated test memory leak (0 leaks now)
- **v0.195.0** — Bug fixes & quality: fixed SQLite UNSIGNED test assertion (backtick→double-quote), fixed Mermaid docs memory leak (missing defer), fixed parser @if conditional block memory leak (15→1 allocations), fixed parser internal ArrayList buffer leaks (BlockState deinit, stripEngineTokens deinit, parse method cleanup), updated Zig package manager roadmap item
- **v0.194.0** — Quality & documentation: added tune.zig unit tests (5 new), integrated validate_views.zig into test suite, synced documentation (test counts, pass lists, leaf module paths), added Db2/MSSQL dialect behavior docs
- **v0.193.0** — WASM fixes & formatter enhancement: fixed `rune_diff` and `rune_migrate` WASM compilation bug (called non-existent `computeDiff` instead of `diff`, wrong argument order); enhanced .ss formatter with proper `@if`/`@endif` block handling (root-level, not indented), `+` doc directive indentation, and block boundary detection; added 5 formatter golden tests and 15 unit tests
- **v0.192.0** — Quality & API completeness: fixed `isSnakeCase` lint helper (rejects consecutive underscores, leading digits, leading/trailing underscores); expanded WASM API with `rune_diff`, `rune_migrate`, `rune_reverse`, `rune_lint` exports; added `validate_views` semantic pass (duplicate view detection, FK table reference validation); fixed LSP dispatch table type mismatches (10 request handlers now use adapter pattern); added inline tests for `isSnakeCase` and WASM exports
- **v0.191.0** — Neovim plugin, conditional schema blocks & docs ER diagrams: created Neovim plugin with LSP integration (lspconfig setup, keybindings for gd/K/rn, commands for Generate/Validate/Lint); added `@if(dialect=pg|sqlite)` conditional schema blocks (parser support, `resolve_conditionals` semantic pass, dialect-aware field filtering); added Mermaid ER diagram generation to docs generator; synced npm package version (0.182.0 → 0.191.0)
- **v0.190.0** — Test coverage enhancement: added 26 new tests for under-tested modules (codegen/columns, pipeline/handlers, reverse/template_extraction, parser/parse_template); improved test coverage for column rendering defaults, CHECK constraints, template extraction logic, and template header parsing
- **v0.189.0** — Lint rules & diff engine: added `nullable-column-default` lint rule (warns when nullable non-PK columns have no explicit DEFAULT); added `timestamp-naming` lint rule (warns when datetime columns don't follow `created_at`/`updated_at` naming convention); added custom type diff support (tracks added/dropped/modified custom types in SchemaDiff with text/JSON/SARIF/markdown formatters); fixed VERSION file mismatch (was 0.187.0, should be 0.188.0)
- **v0.188.0** — Validate enhancement & lint rules: added `--per-table` flag to `rune validate` for per-table field/constraint breakdown; added `column-default-required` lint rule (warns when non-PK, non-nullable columns have no explicit DEFAULT); added `index-naming` lint rule (warns when index names don't follow `<table>_<columns>` convention); fixed `diff/engine.zig` rename detection bug (AutoHashMap key type mismatch); fixed `lint/rules.zig` Zig 0.16 `lowerString` API compatibility; fixed `pipeline/handlers.zig` missing `fmt` import
- **v0.187.0** — Quality consolidation & test coverage: standardized error output across modules (main.zig, watch.zig, handlers.zig, config.zig, init.zig, lint_cmd.zig) to use consistent `fmt.printError`/`fmt.printWarn` format; added `view-no-select` lint rule (warns when views have no SELECT statement); refactored config parsing to eliminate duplication between `parseConfig` and `warnUnknownKeys` via shared `TomlLineIterator`; verified existing tests for `diff/plan.zig` and `codegen/parallel.zig` already cover critical modules
- **v0.186.0** — Architecture refactoring & quality: table-driven LSP method dispatch (replaced 22-branch if-else chain with dispatch table), data-driven lint rule dispatch (replaced 22 repetitive guard-then-call blocks with dispatch table), PassContext.init() method for explicit initialization, WASM error reporting (rune_last_error() export), table-level rename detection in diff engine (70% field overlap threshold), rename display in text/JSON/SARIF diff formatters
- **v0.185.0** — Quality & compilation fixes: fixed 2 test compilation errors (std.Thread.Mutex → std.atomic.Mutex for Zig 0.16 compatibility, varchar_explicit → varchar field name mismatch), fixed fragile `undefined` in PassContext by initializing symbol_table with empty SymbolTable, improved `--check` mode in reverse pipeline to produce meaningful output (was silently returning), verified all 1362 tests pass
- **v0.184.0** — BufferPool parallel extension & quality: extended BufferPool to parallel codegen path (mutex-protected acquire/release for thread-safe buffer reuse), added graceful error recovery with actionable suggestions (OOM, file not found, access denied, disk full), added `--dry-run` flag to `rune generate` command for previewing output without writing files, created schema cookbook with common patterns (multi-tenant, soft delete, audit trail, RBAC, polymorphic associations), updated ARCHITECTURE.md with BufferPool and error recovery documentation
- **v0.183.0** — Quality & code cleanup: fixed SqlParser memory leak (added `deinit()` method with `owns_src` tracking), fixed 3 test compilation errors (`getTemplate` visibility, `StringHashMap.put` API, pass_manager writer-dependency test), fixed 4 incorrect test expectations in `sql_parser_helpers_test.zig`, extracted `lineNoToZeroBased` helper in LSP module (replaced 15+ instances of 1-based to 0-based line conversion), extracted `lintOutput` helper in `lint_cmd.zig` (deduplicated 3-way output format block)
- **v0.182.0** — Quality & test infrastructure: enhanced pass_manager tests (5 new tests for access validation, unique names, dependencies), added CLI lint_cmd and init unit tests, added parser sql_parser_helpers tests (35+ tests), fixed build.zig.zon version mismatch, synced npm package version
- **v0.181.0** — Lint rules & diff enhancements: added `fk-naming` rule (warns when FK columns don't follow `<table>_id` naming convention), added `bool-default` rule (warns when boolean columns have no explicit default value), added `--stat` flag as alias for `--summary` in diff/migrate commands
- **v0.180.0** — Lint rule enhancements: added `index-column-missing` rule (warns when indexes reference columns not defined in the table), added `naming-prefix` rule (warns about anti-pattern table name prefixes like tbl_, t_, tb_), improved `toCamelSingular` to handle irregular plurals (categories→category, quizzes→quiz, addresses→address, men→man)
- **v0.179.0** — Validate JSON output & reverse check: added `--format json` to `rune validate` for CI/CD tooling, added `--check` flag to `rune reverse` for CI gate mode (exit 1 on errors), added `column-length` lint rule (warns on string fields without explicit length for cross-dialect compatibility)
- **v0.178.0** — io.zig cleanup & IR type tests: simplified file reading (removed mmap duplicate copy), fixed mmap resource leak on Linux, added 28 unit tests for TypedAst and ResolvedAst IRs (was zero coverage), documented tune.zig and watch.zig in ARCHITECTURE.md
- **v0.177.0** — Type system unification: added `TypeCategory` enum and `category()` method to `TypeInfo`, added `categoryFromSym()` for raw symbol classification, added `rev()` helper for auto-computing category in REVERSE_MAP, fixed blob/raw_sql classification
- **v0.176.0** — Doc directive & enhanced documentation: added `+` doc directive for structured multi-line documentation on tables, fields, templates, and views; enhanced docs generator with table of contents, cross-references, and `doc` field priority over `: comment`; added `--format json` output for `rune docs`; updated EBNF grammar with `doc_decl` production
- **v0.175.0** — Code quality & deduplication: extracted `shouldEmitDefault` shared helper, removed 4 redundant `writeDefault` wrappers across ORM generators, extracted shared `findNameInLine` into LSP helpers, removed `map_data.zig` shim, fixed TypeORM duplicate index branch, fixed Windows file URI handling
- **v0.174.0** — LSP precision & quality: precise column ranges for references/highlights (FK field names instead of full lines), dialect-aware hover SQL types (respects server dialect instead of hardcoded MySQL), multi-column FK go-to-definition support, precise column selection ranges in document symbols, 4 new FK-related LSP feature tests
- **v0.173.0** — LSP quality & parser cleanup: fixed hardcoded URI in `writeCodeAction`, replaced magic number 100 with actual line lengths in `references.zig`/`highlights.zig`, replaced static256 arrays with dynamic `ArrayList`, extracted shared `getLineText`/`formatFlagsForHover` into `helpers.zig`, extracted shared `locFromLine` into `parser/loc.zig`
- **v0.172.0** — `rune tune`: auto-template extraction — finds fields co-occurring in most tables and extracts them into `% base` template, rewrites .ss file with `#base table` references
- **v0.171.0** — Stats per-table: added `--per-table` flag to `rune stats` for per-table breakdown (fields, types, constraints per table), supports JSON/Markdown/text output formats
- **v0.170.0** — Lint enhancements: added `serial-type` rule (warns on PostgreSQL-specific serial types for cross-dialect compatibility), added `table-name-length` rule (configurable max table name length, default 64), added LSP features facade tests (7 new tests covering document symbols, hover, completions, go-to-definition, references, highlights)
- **v0.169.0** — MSSQL IDENTITY fix: fixed SQL parser to recognize `IDENTITY(seed, increment)` as column modifier (was mis-parsed as separate column), implemented MSSQL `emitAutoIncrement` for forward codegen, updated all 3 MSSQL reverse golden test files
- **v0.168.0** — Quality & polish: fixed DocumentManager memory leak on document reopen, added LSP compile service tests (3 new), pipeline edge case tests (3 new), enhanced LSP hover for FK references (shows target column type and constraints), updated documentation
- **v0.166.0** — Memory safety & buffer pool optimization: fixed `generateTypedView` buffer leak for UNION/INTERSECT/EXCEPT views, added `StreamingCodegen.deinit` and fixed 4 parallel path leaks, extended BufferPool to default SQL codegen path, 6 new view codegen unit tests, synced all packaging manifests to v0.166.0
- **v0.163.0** — Watch directory mode (`--recursive` tracks all .ss files, per-file hash changes, error streak tracking), init template presets (`--template blog|ecommerce|rest-api`)
- **v0.162.0** — Pipeline split & optimization: extracted output handlers from `pipeline/forward.zig` (520 lines) into `pipeline/handlers.zig` (270 lines) for single-responsibility, optimized O(n²) column lookups in `validate_indexes.zig` to O(n) via StringHashMap, added tests for `pipeline/handlers.zig` (formatValidateResult)
- **v0.161.0** — Quality & architecture polish: split `lint_test.zig` monolith (1,018 lines) into 3 focused test files (`lint/rules_test.zig`, `lint/format_test.zig`, `lint/config_test.zig`), extracted LSP request handlers from `server.zig` into `handlers.zig`, documented lint module in ARCHITECTURE.md, organized tests.zig with section comments
- **v0.160.0** — Lint module split: extracted 1017-line `lint.zig` monolith into 4 focused sub-modules (`lint/rules.zig`, `lint/format.zig`, `lint/config.zig`, `lint/fix.zig`), extracted lint CLI handler from `main.zig` into `cli/lint_cmd.zig`, shared JSON escape helper eliminates duplication across formatters
- **v0.159.0** — LSP quality & infrastructure: registered LSP tests in zig build test, fixed memory leaks and ownership bugs in LSP modules, added grammar rules for custom types and engine directives, synced all packaging versions
- **v0.158.0** — Lint auto-fix & init improvements: `rune lint --fix` auto-corrects no-pk and no-timestamps issues, `--dry-run` preview mode, `rune init --output-dir` creates starter schemas in subdirectories
- **v0.157.0** — Quality & bug fixes: OpenAPI extension fix (.yaml→.json), LSP wordAtCursor/detectContext bug fixes, Zig 0.16 compatibility fixes, new generator tests (CHECK constraints, default formatting)
- **v0.156.0** — Quality & polish: `rune format --check` for CI, config error propagation, LSP formatting logging, `catch unreachable` cleanup
- **v0.155.0** — Documentation fixes: migration guide syntax correction, packaging manifest sync, all-dialect benchmark baselines
- **v0.153.0** — LSP feature enrichment: rename support, context-aware completions, rich hover, FK index code action
- **v0.152.0** — VS Code LSP integration (completion, hover, diagnostics), handleCodeAction bug fix, new LSP tests
- **v0.151.0** — TextMate grammar, VS Code extension (syntax highlighting, commands), language configuration
- **v0.150.0** — Docker image, migration guide, package manager support (Homebrew, Scoop, npm)
- **v0.149.0** — FlagRegistry pattern, weighted confidence scoring, test suite sync
- **v0.148.0** — ErrorFormatter integration, CLI consolidation, confidence score improvements
- **v0.147.0** — LSP Code Actions (quick fixes for common schema issues)
- **v0.145.0** — LSP Document Symbols, Completion, Hover, Go-to-Definition
- **v0.144.0** — LSP Language Server foundation (JSON-RPC, diagnostics, document sync)
- **v0.143.0** — WASM cross-compilation, Windows CI, ARM64 CI
- **v0.142.0** — Empty table lint, table comment lint, enhanced docs generator
- **v0.141.0** — Smart generator extensions, duplicate index lint, watch mode logging
- **v0.140.0** — Markdown diff stats fix, lint index fix, memory leak fixes
- **v0.139.0** — Live database diff via stdin, in-memory diff pipeline, `rune stats --summary`
- **v0.138.0** — Expanded lint rules (FK cascade, nullable PK, orphan type)
- **v0.137.0** — Wide table lint, enum case lint, SARIF output, diff-aware lint, lint config
- **v0.136.0** — `rune lint` subcommand with 4 initial rules
