# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.170.0 (2026-08-09) — 31,800+ lines production Zig, 1246+ tests, 32 test suites.

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
- [ ] npm package — `npx rune schema.ss`
- [x] Docker image — `ghcr.io/rune-lang/rune:latest` (v0.150.0)
- [ ] Zig package manager — `build.zig.zon` for dependency consumption

### Documentation

- [ ] Interactive tutorial — web-based walkthrough with live examples
- [x] Migration guide — from SQL DDL, Prisma, Knex to Rune `.ss` (v0.150.0)
- [ ] Cookbook — common patterns (multi-tenant, soft delete, audit trail)
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

- [ ] LSP-based setup — `lspconfig` integration
- [ ] Treesitter grammar — `.ss` file highlighting
- [ ] Keybindings — `gd` (go-to-def), `K` (hover), `<leader>rn` (generate)

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
- [ ] Conditional schemas — `@if(dialect=pg)` blocks for dialect-specific fields
- [ ] Schema documentation — `@doc` directive for inline documentation generation

### Pipeline Extensions

- [ ] SQL formatting — `rune format --dialect pg` for dialect-aware SQL formatting
- [ ] Schema visualization — generate ER diagrams from `.ss` files
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
- [~] Zero-allocation codegen path — reuse buffers across compilations (BufferPool extended to default path, v0.166.0)
- [ ] Incremental compilation — recompile only changed tables

### Code Quality

- [x] Remove all `catch unreachable` in production code (v0.39.0–v0.105.0)
- [x] Remove all unsafe `@intCast`/`@enumFromInt` in production code (v0.80.0)
- [x] Named constants for magic numbers (v0.80.0)
- [x] Eliminate `std.process.exit` in library code (v0.80.0–v0.103.0)
- [x] Formalize IR versioning — schema for forward/backward compatibility (v0.108.0)
- [x] Memory leak audit — reduce remaining leaks toward zero (v0.123.0)
- [x] Fuzz testing expansion — longer runs, more seed variety (v0.123.0)
- [ ] Production error recovery — graceful handling of OOM, file system errors
- [ ] Test coverage analysis — measure and enforce minimum coverage thresholds

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

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1: Core Solidification | ✅ Complete | 9/9 | 0 |
| 2: Extended Dialect Support | ✅ Complete | 14/14 | 0 |
| 3: ORM & API Schema Output | ✅ Complete | 13/13 | 0 |
| 4: Incremental & Live Workflows | ✅ Complete | 10/10 | 0 |
| 5: Developer Experience | ✅ Complete | 13/13 | 0 |
| 6: Ecosystem & Community | 🔲 Planned | 2/9 | 7 |
| 7: Editor Extensions | 🔲 Planned | 7/10 | 3 |
| 8: Language Evolution | 🔲 Planned | 0/8 | 8 |
| Architecture Targets | 🟡 Ongoing | 12.5/14 | 1.5 |
| Technical Debt | 🟡 Partial | 3/5 | 2 |
| **Total** | | **83.5/105** | **21.5** |

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
