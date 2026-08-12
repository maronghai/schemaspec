# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.280.0 (2026-08-12) — 67,100+ lines production Zig, 1,929+ tests, 60 lint rules, 38 test suites.

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

Build the community and ecosystem around Rune. **In progress — 7/11 items done.**

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

- [x] RFC process — formal proposal mechanism for language changes (v0.243.0)
- [ ] Schema registry — shared template library
- [ ] Playground sharing — share `.ss` snippets via URL

---

## Phase 7: Editor Extensions 🔲

Extend the LSP foundation into full editor experiences. **In progress — 11/13 items done.**

### VS Code Extension

- [x] Syntax highlighting — TextMate grammar for `.ss` files (v0.151.0)
- [x] Completion — wire LSP completion into VS Code's IntelliSense (v0.152.0)
- [x] Diagnostics — squiggly lines for errors and warnings (v0.152.0)
- [x] Commands — `Rune: Validate`, `Rune: Generate`, `Rune: Init` (v0.151.0)
- [x] Rename — rename table/column with FK reference updates (v0.153.0)
- [x] Enhanced completion — context-aware FK targets, template refs, prefix filtering (v0.153.0)
- [x] Rich hover — SQL DDL preview, FK relationship details, view SQL (v0.153.0)
- [x] Inlay hints — show resolved SQL types inline in the editor (v0.232.0)

### Neovim Plugin

- [x] LSP-based setup — `lspconfig` integration (v0.191.0)
- [x] Treesitter grammar — `.ss` file highlighting (v0.256.0)
- [x] Keybindings — `gd` (go-to-def), `K` (hover), `<leader>rn` (generate) (v0.191.0)

### JetBrains IDE Plugin

- [ ] IntelliJ-based schema editor — code completion, inspections
- [ ] Integration with LSP server — reuse existing `rune lsp` binary

---

## Phase 8: Language Evolution 🔲

Extend the `.ss` language and pipeline for new use cases. **In progress — 4/9 items done.**

### Generator Plugin System

- [ ] User-defined generators via Zig plugins or WASM modules
- [ ] Template overrides — `.rune-template` files for customizing generator output
- [ ] Generator marketplace — community-contributed generators

### Advanced Schema Features

- [ ] Composite types — reusable field groupings beyond templates
- [x] Schema versioning — `@version` directive for forward/backward compatibility (v0.237.0)
- [x] Conditional schemas — `@if(dialect=pg)` blocks for dialect-specific fields (v0.191.0)
- [x] Schema documentation — `+` doc directive for inline documentation generation (v0.199.0)

### Pipeline Extensions

- [x] SQL formatting — `rune format --dialect pg` for dialect-aware SQL formatting (v0.250.0)
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
- [x] Incremental compilation — recompile only changed tables (v0.278.0)
- [x] Incremental compilation cache persistence — cache survives across sessions (v0.280.0)

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
- [x] FreeBSD CI — test on FreeBSD for server deployments (v0.256.0)
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
- [x] Standardize handler I/O — replaced all `std.debug.print` in handlers with `io_mod.writeOutput` (v0.240.0)
- [x] Standardize handler parameters — added `FormatConfig`, `ExportConfig`, `StatsConfig` structs (v0.240.0)
- [x] Extract config merge logic — moved from main.zig to config_merge.zig for testability (v0.212.0)
- [x] Extract CLI error handling — moved error-to-message mapping from main.zig to cli/errors.zig (v0.234.0)
- [x] Shared SQL type-to-string helper — extracted duplicated SQL type rendering from generators into common.zig (v0.234.0)
- [x] Decompose lint auto-fixer — split monolithic fix() function into per-rule handler functions (v0.234.0)
- [x] Remove SARIF metadata duplication — rule descriptions now derived from LintRule.description() (v0.234.0)

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1: Core Solidification | ✅ Complete | 9/9 | 0 |
| 2: Extended Dialect Support | ✅ Complete | 14/14 | 0 |
| 3: ORM & API Schema Output | ✅ Complete | 13/13 | 0 |
| 4: Incremental & Live Workflows | ✅ Complete | 10/10 | 0 |
| 5: Developer Experience | ✅ Complete | 13/13 | 0 |
| Phase 6: Ecosystem & Community | 🔲 In Progress | 7/11 | 4 |
| 7: Editor Extensions | 🔲 In Progress | 11/13 | 2 |
| 8: Language Evolution | 🔲 In Progress | 4/9 | 5 |
| Architecture Targets | 🔲 In Progress | 21/22 | 1 |
| Technical Debt | ✅ Complete | 15/15 | 0 |
| **Total** | | **117/130** | **13** |

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

- **v0.280.0** — Cache disk persistence & Zig 0.16 API migration: implemented disk persistence for incremental compilation cache (`flushToDisk()`, `loadFromDisk()`, `writeEntryToDisk()`, `writeManifest()`); migrated all cache.zig filesystem operations from deprecated `std.fs.*` to `std.Io.Dir.*` API (Zig 0.16 compatibility); added `io: std.Io` field to `TableCache` struct; added `--cache-dir` CLI flag for custom cache directory; added cache manifest file (`manifest.json`) for fast lookup; extracted `computeScore()` from audit module for testability; added cache module architecture health tests; cleaned up duplicate architecture tests; 1,929+ unit tests pass, benchmarks show no regressions
- **v0.279.0** — Architecture cleanup & layering fix: removed dead code (ErrorFormatter struct in diagnostic/format.zig, unused isUpperSnakeCase re-export in lint/rules.zig, enableDiskCache stub in cache.zig); fixed parser → semantic layering violation by moving semantic/diagnostic.zig to root-level diagnostic.zig (parser files no longer depend on semantic module); updated 20+ import paths across parser, semantic, pipeline, and lsp modules; moved diagnostic_test.zig to root level; 1,929+ unit tests pass, benchmarks show no regressions
- **v0.278.0** — Incremental compilation cache: added table-level content hash cache for streaming compilation (`--cache` flag); cache key = table_name + dialect + SHA-256(content_hash of columns, FKs, indexes); integrated into `StreamingCodegen.generateTable()` to skip codegen on cache hit; added `cache.zig` module with `TableCache`, `CacheKey`, `computeTableHash()`, lookup/store/stats; added `--cache` CLI flag (opt-in, default off); added cache statistics output (hits/misses); 1,928+ unit tests pass, benchmarks show no regressions
- **v0.277.0** — Schema quality reporting & lint expansion: added 2 new lint rules (`fk-unidirectional` warns when a table has outgoing FKs but no incoming references — identifies potentially isolated tables in the schema graph, `column-bad-default` warns when a column default value doesn't match its type category — catches schema design errors early — 60 lint rules total); added Markdown output format for schema health audit (`rune stats --audit --format md` — produces structured Markdown report with findings table and recommendations); added `--min-score` quality gate flag to `rune stats --audit` (exits 1 when health score falls below threshold — enables CI/CD quality gates); expanded architecture health test suite with updated rule count bounds; 1,922+ unit tests pass, benchmarks show no regressions
- **v0.276.0** — WASM test expansion & documentation accuracy: expanded WASM integration tests (lint.zig: 1→4 tests, reverse.zig: 2→4 tests) covering edge cases (invalid input, JSON format, dialect options, MySQL reverse engineering); updated documentation metrics across README.md, ARCHITECTURE.md (test count 1891+→1913+); synchronized packaging versions to 0.276.0 (npm, scoop, vscode, homebrew, build.zig.zon); 1,913+ unit tests pass, benchmarks show no regressions
- **v0.275.0** — Schema audit & lint expansion: added `rune stats --audit` flag for schema health analysis with prioritized recommendations (health score, tables missing PKs, FKs without indexes, missing timestamps, empty enums); added 2 new lint rules (`fk-missing-index` warns when tables have FKs but no supporting indexes, `column-no-comment` warns when columns lack documentation — 58 lint rules total); expanded LSP document symbols to include custom types (~ directives) with enum values as children; 1,908+ unit tests pass, benchmarks show no regressions
- **v0.274.0** — Documentation accuracy & packaging sync: updated ROADMAP.md with accurate metrics (65,400+ lines, 1,899+ tests); synchronized version numbers across all packaging manifests (npm, scoop, vscode, homebrew: 0.273.0→0.274.0, build.zig.zon 0.273.0→0.274.0); 1,899+ unit tests pass, benchmarks show no regressions
- **v0.273.0** — Architecture health expansion & version sync: added 3 new comptime architecture health tests (generator dialect coverage — verifies all 6 SQL dialects appear in at least one generator; pipeline config struct defaults — verifies all 8 config structs are default-initializable; lint fixable rule count — verifies isFixable() works for all rules via comptime iteration); synchronized version numbers across all packaging manifests (npm, scoop, vscode, homebrew: 0.271.0→0.273.0, build.zig.zon 0.272.0→0.273.0); 1,899+ unit tests pass, benchmarks show no regressions
- **v0.272.0** — LSP handler unification & architecture quality: unified all 22 LSP handler signatures to `(self, stdout, id, params)` — eliminated 22 adapter functions (~90 lines of boilerplate) in `lsp/server.zig`; handlers now directly match `HandlerFn` type; expanded architecture health test suite with 5 new comptime checks (lint rule count, formatter module, diff format modules importable, pipeline config defaults, semantic pass structure); updated CLAUDE.md LSP dispatch documentation; 1,899+ unit tests pass, benchmarks show no regressions
- **v0.271.0** — Architecture health & documentation accuracy: expanded architecture health test suite from 7 to 16 comptime checks (DialectBackend vtable field count, all 6 dialect backends importable, 10 WASM sub-modules importable, LSP dispatch table structure, REVERSE_MAP entry count, type registry dialect count, config struct defaults, formatter module, generator metadata validation); fixed CLAUDE.md handler rule counts (validation 7→11, fk 6→9, index 4→5); fixed CLAUDE.md DialectBackend description (33→32 function pointers, quoteChar is data field not function pointer); fixed CLAUDE.md source layout (4→9 handler modules); fixed CLAUDE.md pass count (14→17); fixed ARCHITECTURE.md stale Forward Pipeline line counts (tokenizer 399→251, parser 456→623, template 351→212, type_resolver 189→224, typed_ast 132→101); fixed ARCHITECTURE.md Reverse Pipeline line counts (sql_parser 413→545, reverse_codegen 298→261); updated rune/README.md test count (1882+→1899+); 1,899+ unit tests pass, benchmarks show no regressions
- **v0.270.0** — Documentation accuracy & packaging sync: fixed `lint.zig` barrel comment (42→56 rules); updated ARCHITECTURE.md lint rules table from 19 to complete 56-rule list; fixed ARCHITECTURE.md unit test count (~1,876+→~1,882+); fixed ARCHITECTURE.md lint rules count (51→56); fixed CLAUDE.md lint --fix rule name (index-column-missing→index-missing-fk-columns); updated rune/README.md test count (1,876+→1,882+); fixed root README.md test file count (117→118); synchronized packaging versions (npm, scoop, vscode, homebrew: 0.267.0→0.270.0); 1,882+ unit tests pass, benchmarks show no regressions
- **v0.269.0** — Lint expansion & documentation accuracy: added 2 new lint rules (`column-auto-increment-nullable` warns when auto-increment modifier is used on nullable columns — should be NOT NULL; `table-no-index` warns when a table has no indexes — potential performance issue — 56 lint rules total, 11 fixable); added 6 new unit tests for new lint rules; updated architecture health test comment (51→56 rules); updated documentation with accurate rule and test counts; 1,882+ unit tests pass, benchmarks show no regressions
- **v0.267.0** — Lint rules expansion & architecture quality: added 3 new lint rules (`column-auto-increment-type` warns when auto-increment modifier is used on non-integer types, `column-unique-naming` warns when columns in the same table differ only by case, `fk-on-delete-cascade` warns when FK uses ON DELETE CASCADE with potential data loss risk — 54 lint rules total, 11 fixable); added 8 new unit tests for new lint rules; updated documentation with accurate rule counts; 1,876+ unit tests pass, benchmarks show no regressions
- **v0.266.0** — Architecture cleanup & code quality: extracted shared `compileToTypedAst` helper from duplicate definitions in `pipeline/generate.zig` and `pipeline/handlers.zig` into `pipeline/compile_helper.zig` (DRY fix); replaced `std.process.exit(1)` in `pipeline/generate.zig` with proper error propagation (`error.GeneratorHealthCheckFailed`); fixed double-lint execution in `pipeline/validation.zig` (when `--strict` + `--fix` both active, `lintSchema` now runs once and shares results); removed dead code in `version.zig` (`formatAlloc`, `writeMajorMinor` — private methods never called from production); converted `emitSchemaHeader` and `emitStandaloneIndexes` in `reverse/codegen.zig` from struct methods to free functions (removed unused `self` parameters); fixed zig fmt violations in 5 files; 1,868 unit tests pass, benchmarks show no regressions
- **v0.265.0** — Documentation & packaging synchronization: synchronized version numbers across all 6 packaging manifests (homebrew 0.175.0→0.265.0, scoop 0.175.0→0.265.0, npm 0.254.0→0.265.0, vscode 0.254.0→0.265.0, build.zig.zon 0.262.0→0.265.0); fixed ARCHITECTURE.md internal contradictions (unit test count ~1,808+→~1,868+, colocated files 110→117, MySQL golden 86→85, PG golden 87→86, roundtrip 68→112, reverse confidence 4→3, total ~1,788+→~1,868+); updated rune/README.md and root README.md test file counts (110→117); 1,868 unit tests pass, benchmarks show no regressions
- **v0.264.0** — Lint test infrastructure cleanup: extracted shared test helpers (`makeTestTable`, `makeField`, `makePkField`, `makeFkField`, `makeIndex`, `makeAst`, `findRule`, `countRule`, `findRuleWithSubstring`) from monolithic `lint/rules_test.zig` (2,719 lines, 108 tests) into `lint/test_helpers.zig`; split into 7 focused per-rule-group test files (`rules_structural_test.zig`, `rules_naming_test.zig`, `rules_validation_test.zig`, `rules_fk_test.zig`, `rules_compat_test.zig`, `rules_index_test.zig`, `rules_view_enum_test.zig`); deleted 2,719-line monolithic file; 1,868 unit tests pass, benchmarks show no regressions
- **v0.263.0** — Architecture quality & module decomposition: extracted schema generation logic from `pipeline/handlers.zig` (452 lines) into focused `pipeline/generate.zig` module (single-responsibility for `GenerateConfig`, `handleGenerate`, `generateFromSchema`, `generateFromSchemaBatch`); added architecture health test suite (`tests/architecture_test.zig`) with 7 comptime checks for module API stability (generator registry count, semantic pass count, dialect backend count, lint rule count, public API existence); updated `tests.zig` with new test registrations; 1,860+ unit tests pass, 243 golden tests pass (MySQL, PostgreSQL, SQLite, migration, diff), benchmarks show no regressions
- **v0.260.0** — Lint rule exhaustiveness & generator health: made `LintRule.isFixable()` and `LintRule.lintLevel()` exhaustive switches (new rules must declare fixability and severity explicitly); expanded `generator.check()` to test all 6 dialects (was MySQL-only); 1,850+ unit tests pass, benchmarks show no regressions
- **v0.256.0** — Treesitter grammar & CI expansion: added Treesitter grammar for `.ss` files (syntax highlighting for Neovim, Helix, Zed); grammar covers all syntax elements (schema, type, template, table, view, field, FK, index, composite PK, conditional blocks, version, import, doc directives); created highlights.scm, folds.scm, injections.scm query files; registered unregistered `pipeline/validation_test.zig` in tests.zig; added FreeBSD CI cross-compilation (x86_64 and aarch64 targets) to CI pipeline; 1,820+ unit tests pass, benchmarks show no regressions
- **v0.255.0** — LSP code actions & lint UX: expanded LSP code actions with 9 quick fixes (add PK, add comment, snake_case rename, add timestamps, bool default, nullable default, serial replacement, duplicate index removal, FK index); fixed `findLineEnd` hardcoded value (removed dead function, callers now use `diag.range.end.character`); fixed memory safety in `freeCodeActions` (all `new_text` values now heap-allocated via `alloc.dupe` for uniform freeing); added `--summary` flag to `rune lint` (shows "N warning(s), M error(s)" for CI scripts); added `formatLintSummary` function for consistent summary formatting; 7 new lint format tests (JSON, SARIF, text, summary output); 1,820+ unit tests pass, benchmarks show no regressions
- **v0.254.0** — Lint optimization & rule expansion: optimized `lintDiff` algorithm from O(n*m) to O(n) using StringHashMap for deduplication; added `index-columns-max` lint rule (warns when indexes have more than N columns, configurable threshold default 5); added `index_columns_max` field to LintConfig; updated lint rule count from 45 to 46; 1,820+ unit tests pass, benchmarks show no regressions
- **v0.253.0** — Architecture quality & dependency cleanup: fixed VERSION file inconsistency (was 0.251.0, should have been 0.252.0); cleaned up dead pub functions across 6 modules (io.zig: mmapFile, config.zig: parseConfig/warnUnknownKeys, handlers.zig: generateFromSchema/generateFromSchemaBatch/compileToTypedAst, semantic/analyzer.zig: initVerbose, semantic/diagnostic.zig: printDiagnosticColor, types/ir_version.zig: validateIrVersion, version.zig: formatAlloc/writeMajorMinor — all changed from pub to non-pub for correct visibility); fixed Dialect import path consistency across 4 pipeline modules (diff.zig, migrate.zig, handlers.zig, forward.zig, reverse.zig now import Dialect from dialect/enum.zig instead of codegen.zig); 1,820+ unit tests pass, benchmarks show no regressions
- **v0.252.0** — Lint rules expansion & quality: added 3 new lint rules (`reserved-word` warns when table/column names use SQL reserved words, `column-type-portability` warns about non-portable type choices like MySQL-specific TINYINT/MEDIUMTEXT, `index-missing-fk-columns` warns when tables have FKs but no index on FK columns — 12 fixable rules total); added auto-fix support for `index-missing-fk-columns` rule; added new portability handler module (`lint/handlers/portability.zig`); added 8 new unit tests for new lint rules and format output; 1,820+ unit tests pass, benchmarks show no regressions
- **v0.251.0** — Architecture quality & validation enhancement: extracted validation handlers (handleValidate, handleCheck, ValidateConfig) from pipeline/handlers.zig into pipeline/validation.zig for single-responsibility; added schema summary output to `rune validate` (shows table/field/view/index/FK counts in text mode); fixed I/O consistency (replaced std.debug.print with io_mod.writeOutput in validation fix output); added 12 new unit tests for validation module (ValidateConfig defaults, compilation integration, format output, strict mode, summary formatting); 1,808+ unit tests pass, benchmarks show no regressions
- **v0.250.0** — Formatter enhancement & dialect awareness: added `--write` flag to `rune format` for in-place file editing (like `prettier --write`); added `--dialect <d>` flag for dialect-aware SQL keyword formatting (extends keyword uppercasing to dialect-specific keywords: MySQL `AUTO_INCREMENT`/`UNSIGNED`/`ENGINE`, PostgreSQL `SERIAL`/`RETURNING`/`ILIKE`, SQLite `AUTOINCREMENT`/`VACUUM`/`PRAGMA`, MSSQL `IDENTITY`/`TOP`/`NVARCHAR`, Oracle `NUMBER`/`VARCHAR2`/`SYSDATE`, Db2 `GENERATED`/`IDENTITY`/`CLOB`); integrated dialect-aware formatting into LSP server (document formatting uses server dialect configuration); added 8 new formatter unit tests for dialect-specific keyword handling; added 14 format golden tests (`--write`, `--dialect`, `--check` modes); updated completions for `--write` flag; 1,796+ unit tests pass, benchmarks show no regressions
- **v0.249.0** — Developer experience & watch mode enhancements: added `--fix` flag to `rune validate` (combines schema validation with lint auto-fix in a single command, applies all 11 fixable lint rules); added compile time display to watch mode output (shows milliseconds for initial compilation and per-change recompilation); updated help text with validate --fix examples; added parse test for validate --fix flag; updated golden tests for validate --fix; 1,790+ unit tests pass, benchmarks show no regressions
- **v0.248.0** — Documentation accuracy & ROADMAP correction: fixed ROADMAP summary table counting inconsistency (was 113/119 = 6 remaining, corrected to 113/129 = 16 remaining — actual count across all phases); verified all 108 colocated test files and 1,788+ unit tests pass; benchmarks show no regressions
- **v0.247.0** — Architecture cleanup & validate strict mode: decomposed monolithic `lint/fix.zig` (725 lines) into 4 focused modules (`fix_helpers.zig` for shared types/helpers, `fix_structural.zig` for no-pk/no-timestamps/empty-table, `fix_modifier.zig` for serial-type/bool-default/nullable-default/column-default, `fix_index.zig` for duplicate-index/no-index-fk/duplicate-column); eliminated duplicate `LintFix` type, `isWordBoundary`, `replaceWord`, `tableNeedsFix`, `detectDefaultValue`, `FixMaps`, `buildFixMaps` across modules; consolidated `generator.zig` listing functions (eliminated `listDetailedStderr` duplication via `writeDetailedInfo` delegation); added `validate --strict` mode (exits 1 on lint warnings for CI/CD gate); registered 4 new test files in `tests.zig`; 1,788 unit tests pass, benchmarks show no regressions
- **v0.246.0** — Test coverage & format UX: added 5 unit tests for `lsp/go_to_definition.zig` (FK reference navigation, FK column navigation, non-FK column null, table name line null, same-table FK navigation); improved `rune format --check` with "formatting needed" message; improved `rune format --diff` with "N line(s) would change" summary; 1,785 unit tests pass, benchmarks show no regressions
- **v0.245.0** — LSP test coverage & code quality: extracted shared `wordAtPosition` helper in `lsp/helpers.zig` to eliminate duplicated word-finding logic between `prepareRename` and `getRenameLinks` in `lsp/rename.zig`; fixed `isTableDeclaration` and `isFkReference` functions in `lsp/rename.zig` to support Rune syntax (`#` prefix for tables, `->` for FK references); fixed `getRenameLinks` memory management (now uses `toOwnedSlice` to transfer ownership); added 3 new tests for `lsp/rename.zig` (prepareRename positive cases, FK reference updates); added 2 new tests for `lsp/references.zig` (multiple FK references, table references with FKs); registered 4 new test files in `tests.zig` (lsp/highlights_test.zig, lsp/references_test.zig, lsp/rename_test.zig, pipeline/migrate_test.zig); 1,780 unit tests pass, benchmarks show no regressions
- **v0.244.0** — Architecture quality & lint expansion: added `fk-duplicate` lint rule (warns when a table has multiple foreign keys referencing the same target table — potential junction table pattern); extracted generate command dispatch from main.zig into `handleGenerate()` in pipeline/handlers.zig (handles --list, --check, and generation modes uniformly); fixed `catch unreachable` in export.zig test helper (now uses proper error propagation with `try`); added `list` and `check` fields to `GenerateConfig` struct; 1,780+ unit tests pass, benchmarks show no regressions
- **v0.243.0** — CI optimization & RFC process: restructured CI pipeline (reduced sequential steps from 21 to 12 by combining related test suites); established RFC process for formal language change proposals (rfcs/ directory with template and inaugural RFC-0001); fixed ROADMAP summary table counting inconsistencies (was 109/117, corrected to 113/119); 1,770+ unit tests pass, benchmarks show no regressions
- **v0.242.0** — Architecture quality & deduplication: replaced hardcoded 41-entry SARIF rule list in lint/format.zig with data-driven approach using RULE_INFO from rules.zig (single source of truth); added `lintLevel()` method to LintRule enum for SARIF severity mapping; fixed misleading `count` lint rule description (was "Table has more than 50 columns", now correctly "Table has fewer than minimum field count"); deduplicated WASM tests (removed 17 overlapping tests from wasm.zig, consolidated into wasm_test.zig); completed tests.zig index with 5 previously unlisted files (version.zig, lsp/handlers.zig, pipeline/export.zig, diagnostic/format.zig, cli/flag_registry.zig); 1,770+ unit tests pass, benchmarks show no regressions
- **v0.241.0** — LSP Code Lens & WASM completeness: added `textDocument/codeLens` LSP support with inline action triggers (Validate, Generate SQL, Lint) on file-level and per-table definitions; added `rune_export` WASM export for schema export as JSON/text/markdown; added `rune_docs` WASM export for Markdown documentation generation; added `codeLensProvider` capability to LSP server; added 4 unit tests for code lens generation; 1,767+ unit tests pass, benchmarks show no regressions
- **v0.240.0** — Architecture cleanup & I/O consistency: standardized all handler output to use `io_mod.writeOutput` instead of raw `std.debug.print` (handleFormat diff mode, generateFromSchemaBatch status messages, main.zig generator health check); added `FormatConfig`, `ExportConfig`, `StatsConfig` structs to replace positional parameters (consistent with `CompileConfig`, `ValidateConfig`, `GenerateConfig` patterns); updated documentation with accurate test file counts (103 colocated test files); 1,757 unit tests pass, benchmarks show no regressions
- **v0.239.0** — SQL keyword formatting & quality improvements: added SQL keyword uppercasing to the .ss formatter for content inside @if/@endif conditional blocks (CREATE, TABLE, SELECT, PRIMARY, KEY, etc. are uppercased while Rune type symbols like int, text, varchar remain lowercase); added comprehensive WASM module test coverage (25 new tests for wasm/common.zig: classifyError, storeError/clearError, containsSubstring, parseOption, parseDialectOption, parseDiffFormatOption); added version utility methods (formatAlloc, writeMajorMinor) with unit tests; 1,752 unit tests pass, benchmarks show no regressions
- **v0.238.0** — LSP handler tests & documentation sync: added 11 unit tests for `lsp/handlers.zig` helper functions (`safePositionCast` boundary values, `parsePosition` valid/missing cases, `parseDocumentUri` valid/missing/missing-uri cases); created `lsp/handlers_test.zig` test file and registered in `tests.zig`; fixed stale test count in README.md (1548+ → 1,715+); updated version to 0.238.0; 1,715 unit tests pass, benchmarks show no regressions
- **v0.237.0** — Schema versioning directive: added `@version X.Y.Z` directive for declaring schema version metadata (flowing through AST → ResolvedAst → TypedAst pipeline); version emitted as SQL comment (`-- Schema version: X.Y.Z`) after header; parser correctly handles tokenizer splitting `@version` into `@` and `version` tokens; updated schema spec documentation with version directive examples; 1,705 unit tests pass, benchmarks show no regressions
- **v0.236.0** — LSP code quality & deduplication: extracted `writeDiagnosticAsJson` helper in `lsp/protocol.zig` to eliminate diagnostic serialization duplication (was duplicated in `writePublishDiagnostics` and `writeCodeAction`); added `parseDocumentUri` helper in `lsp/handlers.zig` to extract document URI from LSP params (replaces 18 occurrences of 2-line pattern); 1,705 unit tests pass, benchmarks show no regressions
- **v0.235.0** — Generator deduplication & lint test coverage: extracted `writeDetailedInfo` helper in `generator.zig` to consolidate detailed generator listing logic (used by `listDetailedTo`); added 10 new unit tests for 5 previously uncovered lint rules (cross-dialect-types, column-default-required, unique-constraint, composite-pk, view-no-alias); fixed version mismatch between `build.zig.zon` (was 0.233.0) and `VERSION` file; 1,705 unit tests pass, benchmarks show no regressions
- **v0.234.0** — Architecture cleanup & code deduplication: extracted CLI error handling from `main.zig` into `cli/errors.zig` (reduced main.zig by 150 lines); added shared `writeSqlTypeString` helper to `generators/common.zig` (eliminates SQL type rendering duplication across generators); refactored `generators/docs.zig` and `generators/symbol_index.zig` to use shared helper; decomposed monolithic `lint/fix.zig` (370-line `fix()` function) into per-rule handler functions (`fixSerialType`, `fixBoolDefault`, `fixNullableColumnDefault`, `fixColumnDefaultRequired`, `fixNoIndexFk`) with extracted `buildFixMaps` pre-scan; expanded SARIF output in `lint/format.zig` to include all 41 lint rules (was 14); SARIF rule descriptions now derived from `LintRule.description()` (single source of truth); added 6 new unit tests for `cli/errors.zig`; 1,690+ unit tests pass, benchmarks show no regressions
- **v0.233.0** — Generator metadata & lint bug fix: added `version` and `author` metadata fields to `Generator` struct (displayed in `rune generate --list` output); fixed `duplicate-column` auto-fix bug (was marked fixable but handler was not implemented — now properly removes duplicate column declarations); added `unique-constraint` lint rule (warns when a UNIQUE constraint targets a column that is already the primary key — redundant); added `composite-pk` lint rule (warns when a table has multiple auto-increment primary keys — invalid); 41 lint rules total, 11 fixable; 1,690+ unit tests pass, benchmarks show no regressions
- **v0.232.0** — LSP inlay hints & architecture quality: added `textDocument/inlayHint` LSP support that shows resolved SQL types inline in the editor (e.g., `n` shows as `-> int`, `s64` shows as `-> varchar(64)`); added `InlayHint` type to LSP protocol; added `inlayHintProvider` capability to LSP initialize response; added 5 unit tests for inlay hint generation and serialization; added comment explaining generator listing duplication rationale; 1,685 unit tests pass, benchmarks show no regressions
- **v0.231.0** — Generator deduplication & architecture cleanup: extracted `writeOrmDefault` helper to eliminate 5-line default value emission pattern across 5 ORM generators; created `ImportTracker` struct in `common.zig` to consolidate ~80 lines of duplicated import-tracking logic; moved `irregulars` table to module-level const in `toCamelSingular`; fixed `parseInList` memory leak in `writeColumnPropJson`; refactored drizzle/typeorm/sqlalchemy/knex generators to use `common.writeComment`, `common.writeOrmDefault`; added `parsePosition` helper in LSP handlers (eliminated 8 occurrences of 3-line position parsing); removed dead `shouldCompile` stub and dead defer arm in server.zig; removed dead `parseOnly` function in forward.zig; added named `CompileInternalResult` struct; added `Stats.zero` comptime constant; 1,680 unit tests pass, benchmarks show no regressions
- **v0.230.0** — Architecture quality improvements: unified generator listing functions (eliminated ~40 lines of duplication between `listDetailed` and `listDetailedStderr`); created `GenerateConfig` struct in `pipeline/handlers.zig` to replace 8 positional parameters with a named struct (consistent with `CompileConfig` and `ValidateConfig` patterns); added unified `handleGenerate()` entry point; verified `catch unreachable` only exists in test code (not production); 1,680 unit tests pass, benchmarks show no regressions
- **v0.229.0** — Lint handler refactoring & new rules: split `lint/handlers/validation.zig` (586 lines) into 4 focused modules (`fk.zig`, `index.zig`, `view.zig`, `enum.zig`) for better maintainability; added `column-boolean-naming` lint rule (warns when boolean columns don't use `is_`/`has_`/`can_` prefix convention); added `fk-depth` lint rule (warns when FK reference chain exceeds 3 levels); 10 new unit tests (1,685 total); benchmarks show no regressions
- **v0.228.0** — Lint rules expansion: added `view-select-star` lint rule (warns when views use SELECT * — prefer explicit column lists for portability and schema evolution); added `enum-value-duplicate` lint rule (warns when a custom type has duplicate enum values — helps catch copy-paste errors); 5 new unit tests (1,675 total); benchmarks show no regressions
- **v0.227.0** — Architecture review & quality: comprehensive architecture analysis confirmed clean IR boundaries, pluggable generator registry, and data-driven dispatch patterns; verified all code quality issues (catch unreachable, std.process.exit) are resolved in production code; confirmed pipeline modules have comprehensive test coverage (100 test files, 1,670 tests); benchmarks show no regressions
- **v0.226.0** — LSP enhancements & semantic quality: added `workspace/symbol` LSP support for searching all tables, columns, views, and custom types across the workspace (case-insensitive substring match); added `textDocument/signatureHelp` LSP support with parameter hints for field declarations and FK references; added `validate_unused_enums` semantic pass that warns about custom types (~) defined but never referenced in any table field; fixed missing capability serialization for `referencesProvider`, `documentHighlightProvider`, `foldingRangeProvider`, and `typeDefinitionProvider` in LSP initialize response; 10 new unit tests (1,670 total); benchmarks show no regressions
- **v0.225.0** — Lint rules expansion: added `view-naming` rule (warns when views don't follow `<entity>_view` or `v_<entity>` convention); added `duplicate-column` rule (warns when a table has columns with the same name, fixable); added 5 new unit tests (1,660 total); benchmarks show no regressions
- **v0.224.0** — Data-driven help system: replaced 200-line if-else chain in `printSubcommandHelp` with data-driven `COMMAND_HELP` registry (17 commands, zero string matching); fixed help text inaccuracies (lint rule count 30→33, fixable count 8→9); removed orphaned `-T` flag from global help; eliminated duplicate `DocsFormat` enum between `cli/types.zig` and `pipeline/handlers.zig`; added missing help sections for export, docs, stats, version commands; 1,655 unit tests pass, benchmarks show no regressions
- **v0.222.0** — Lint infrastructure expansion: extracted shared field helpers (`isPrimaryKey`, `isNullable`, `hasExplicitDefault`) to eliminate 60+ lines of duplicated modifier-checking code across 5 validation functions; expanded auto-fix from 8 to 10 rules (added `column-default-required` with type-aware defaults and `no-index-fk` with automatic index creation); enhanced lint text formatter with "(fixable)" indicators next to fixable rules; added `detectDefaultValue` helper for type-aware default value selection; 10 new unit tests for helpers and auto-fix rules
- **v0.221.0** — Code quality audit: comprehensive review of production code for undefined fields and unreachable panics; confirmed all `= undefined` usages are safe Zig idioms (stack buffers immediately filled by formatting functions, conditionally initialized variables used only in initialized branches); confirmed `catch unreachable` only exists in test helper functions; fixed formatting issue in semantic/analyzer.zig; 1,651 unit tests pass, benchmarks show no regressions
- **v0.220.0** — Diff engine optimization & WASM test coverage: optimized `computeFieldOverlap` in diff engine from O(n×m) to O(n+m) using StringHashMap for field name lookup; added 18 new WASM unit tests covering `classifyError` (5 error categories), `storeError`/`clearError` lifecycle, and `parseOption` edge cases (empty key, empty value, multiple keys, equals in value); made `classifyError` public for testability; 1,651 unit tests pass, benchmarks show no regressions
- **v0.219.0** — Version struct & architecture hardening: added `Version` struct to `version.zig` with `major`/`minor`/`patch` fields, `parse()` for string parsing, `format()` for string output, and `order()`/`gte()`/`lte()`/`gt()`/`lt()`/`eq()` comparison methods; added `CURRENT` comptime constant for compile-time version access; added 15 new unit tests for Version parsing, formatting, and comparison; 1,633 unit tests pass, benchmarks show no regressions
- **v0.217.0** — LintConfig data-driven refactoring & generator CLI improvements: replaced 33 individual boolean fields in `LintConfig` with a data-driven `RuleSet` struct indexed by `LintRule` enum; eliminated 33-arm `isRuleEnabled` and `setRuleEnabled` switches; simplified `applyLintRules` to use `RuleSet` methods; unified `rune generate --list` to use `generator.listDetailedStderr()` for rich output showing extension, category, and dialects; added `rune generate --check` flag for generator health validation; added `listDetailedStderr()` function to generator module; 7 new RuleSet unit tests; 1,619 unit tests pass, benchmarks show no regressions
- **v0.216.0** — Architecture hardening & code quality: eliminated `= undefined` fields in PassContext (replaced with required fields via `init()`); extracted export/validation formatters from `pipeline/handlers.zig` into `pipeline/export.zig`; extracted `LintRule` enum from `lint/config.zig` into `lint/rule_enum.zig`; added `safePositionCast` helper for LSP position safety; hardened WASM error classification with structured `classifyError` function; named rename detection threshold constant (`RENAME_OVERLAP_THRESHOLD`); updated all test files to use `PassContext.init()`; new unit tests for export formatters and LintRule metadata; 1,601+ unit tests pass, benchmarks show no regressions
- **v0.215.0** — WASM module refactoring & lint rules expansion: refactored 800-line wasm.zig monolith into wasm/ directory with 8 focused sub-modules (common, error, compile, diff, reverse, lint, format, generate); added 3 new lint rules (view-no-alias, fk-self-reference, enum-empty — 33 total); updated ARCHITECTURE.md with new wasm module structure; 1,601 unit tests pass, benchmarks show no regressions
- **v0.214.0** — Generator registry enhancement & export command: added `category` (schema/standalone) and `dialects` metadata to all 11 generators in `REGISTRY`; added `listDetailed()` for rich `rune generate --list` output showing extension, category, and supported dialects; added `check()` function for generator health validation; added `rune export` command with JSON/text/markdown output formats for schema tooling integration; refactored `main.zig` dispatch with `resolveInputPath` and `readFileOrStdin` helpers (reduced dispatch function by 30 lines); 1,600+ unit tests pass, benchmarks show no regressions
- **v0.213.0** — WASM API completeness & CLI enhancement: added `rune_format` export (auto-format .ss schema text via WASM), `rune_tune` export (auto-extract templates via WASM), `rune_generate` export (pluggable generator dispatch via WASM — prisma, drizzle, openapi, etc.); added `--json` flag to `rune version` for machine-readable JSON output; added 11 new WASM unit tests; 1,597 unit tests pass, benchmarks show no regressions
- **v0.212.0** — Config merge extraction & testability: extracted config merge logic from main.zig into config_merge.zig (7 merge cases: dialect, quiet, json_errors, color, target, stream, parallel); added 11 unit tests verifying CLI precedence semantics; updated CLAUDE.md with Config Merge pattern documentation; 1,586 unit tests pass
- **v0.211.0** — Watch command enhancement & quality improvements: fixed watch mode missing `--import-path` support (schemas with @import directives now work correctly in watch mode); added `--stream` flag to watch command for streaming compilation (decoupled from `--parallel`); added color mode support to watch command; added SARIF format output for `rune validate --format sarif` (CI/CD integration); added new watch module unit tests (stream, import_paths); 1,575 unit tests pass
- **v0.210.0** — WASM API completeness & bug fixes: added `rune_stats` export (compile schema, return statistics as JSON), `rune_validate` export (validate schema, return results as JSON), `rune_last_error_code` export (numeric error codes for programmatic error handling); fixed parser memory leak in `stripEngineTokens`; refactored WASM module to use new format modules; extracted option-parsing helpers to reduce boilerplate; 15+ new WASM unit tests (1,560+ total)
- **v0.209.0** — Parser memory leak fix & error output unification: fixed `BlockState.reset()` in `parser.zig` that allocated a new `parents_buf` on each call without reusing capacity (changed to fixed-size `[4][]const u8` array); fixed `parseTemplateHeader` in `parse_template.zig` to properly free temporary `parents_buf` allocation; unified config warnings in `config.zig` to use `fmt.printWarn` from `diagnostic/format.zig`; 1,548 unit tests pass
- **v0.208.0** — Lint rules refactoring & build cleanup: split `lint/rules.zig` (1,052 lines) into 4 category-based handler modules (`structural.zig`, `naming.zig`, `validation.zig`, `compat.zig`); removed unused `run_golden` artifact from `build.zig`; 1,548 unit tests pass
- **v0.207.0** — Critical template inheritance bug fix: fixed arena allocator memory corruption caused by `BlockState.reset()` and `BlockState.deinit()` freeing `parents_buf` via `alloc.free()` while previously flushed templates still referenced it through `Template.parents` slices; the arena allocator's `free` moved the end pointer backward, corrupting previously allocated data; all 5 template inheritance golden tests now pass (11-template-inherit, 12-template-deep, 13-template-extends, 51-inherit-override, 66-template-mixins); 1,548 unit tests pass, 447 golden tests pass across all 6 dialects
- **v0.206.0** — Test coverage expansion & documentation accuracy: added unit tests for `dialect/enum.zig` (parseDialect, alias resolution, writeHeader), `utils.zig` (optionalStrEq, jsonEscapeString), `cli/types.zig` (Command enum, ParsedArgs defaults, COMMAND_REGISTRY, GlobalFlags); fixed stale documentation metrics across CLAUDE.md, README.md, ARCHITECTURE.md (test file count 93→100, test count 1,438+→1,548+); 20 new unit tests (1,548 total)
- **v0.205.0** — LSP feature completeness & documentation accuracy: added `textDocument/foldingRange` support (code folding for table blocks, template blocks, @if/@endif conditional blocks); added `textDocument/typeDefinition` support (navigate from custom type fields to ~ definitions); fixed CHANGELOG.md gap (added v0.195-v0.204 entries); fixed ROADMAP.md inconsistencies (Phase 6/7/8 descriptions, summary table totals); 7 new unit tests (1522+ total)
- **v0.204.0** — Architecture hardening & critical bug fixes: fixed plan inversion `type_def = undefined` (rollbacks now preserve custom type definitions); implemented `emitEnumValues` to extract actual enum values from CustomType definitions instead of emitting placeholders; fixed MSSQL `sp_rename` to include 'COLUMN' object type parameter; improved lint config error reporting (invalid numeric thresholds now return errors instead of silently ignoring); removed `std.process.exit` from `cli/lint_cmd.zig` library code (now returns errors for testability); added `StrictWarnings` error type for lint strict mode; 3 new unit tests for plan inversion (1520+ total)
- **v0.203.0** — Architecture hardening & migration pipeline: added custom type migration support (CREATE/DROP TYPE SQL generation for PostgreSQL, MySQL comments for unsupported dialects); deduplicated ORM FK detection loops (knex, sqlalchemy now use shared `common.findFkRefTable`); added 8 new semantic pass tests (resolve_conditionals: 4 tests, validate_views: 4 tests); added FK field count validation (warns when FK fields count doesn't match ref_fields count); 12 new tests total (1514 pass)
- **v0.202.0** — Lint rule metadata consolidation: added `description()` method to `LintRule` enum (single source of truth for rule descriptions); added `RuleInfo` struct and `RULE_INFO` constant in `lint/rules.zig` (derives name, description, fixable from `LintRule`); refactored `showAllRules` and `initLintConfig` in `lint_cmd.zig` to iterate `RULE_INFO` instead of maintaining hardcoded lists; added 4 unit tests for `RULE_INFO` consistency; 1502 tests pass, benchmarks show no regressions
- **v0.201.0** — Lint UX & rule infrastructure: added `--show-rules` flag to list all 30 rules with descriptions and fixability status; added `--init` flag to generate starter `.rune-lint.toml` config file; added `cross-dialect-types` lint rule (warns about MySQL-specific types like UNSIGNED, TINYINT, MEDIUMTEXT that don't port to other dialects); enhanced lint summary line to show fixable count; updated help text with all 30 rules; 4 new unit tests
- **v0.200.0** — Architecture hardening: fixed ARCHITECTURE.md stale pass list (added `template_type_conflict`, fixed `resolve_conditionals` position, updated count from 14 to 16); fixed main.zig `std.io.getStdErr()` API incompatibility (Zig 0.16 uses `std.Io.File.stderr()`); all 1498 tests pass, benchmarks show no regressions
- **v0.199.0** — LSP doc hover & lint rules expansion: added `+` doc content to LSP hover popups (tables, columns, views show doc as markdown blockquote); added `enum-value-naming` lint rule (warns when custom type enum values use lowercase instead of UPPER_CASE); added `fk-null` lint rule (warns when foreign key columns are nullable); added 4 new unit tests (1498 total)
- **v0.198.0** — Lint auto-fix expansion & migrate integration: expanded `rune lint --fix` from 3 to 8 fixable rules (added serial-type, bool-default, nullable-column-default, duplicate-index, index-column-missing); added `LintRule.isFixable()` method for rule introspection; added `template_type_conflict` semantic pass for table-to-template type mismatch detection; integrated auto-lint into `rune migrate` pipeline (auto-fixes applied to new schema before migration, disable with `--no-lint`); added `template_ref` field to ResolvedTable for template tracking; fixed pre-existing empty-table fix test bug; 10 new unit tests (1492 total)
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
