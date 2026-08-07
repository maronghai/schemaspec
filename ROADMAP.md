# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.148.0 (2026-08-07) — 27,500+ lines production Zig, 1153+ tests, 29 test suites.

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

## Phase 7: Editor Extensions 🔲

Extend the LSP foundation into full editor experiences.

### VS Code Extension

- [ ] Syntax highlighting — TextMate grammar for `.ss` files
- [ ] Completion — wire LSP completion into VS Code's IntelliSense
- [ ] Diagnostics — squiggly lines for errors and warnings
- [ ] Commands — `Rune: Validate`, `Rune: Generate`, `Rune: Init`

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

- [ ] SQL formatting — `rune fmt --dialect pg` for dialect-aware SQL formatting
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
- [ ] Zero-allocation codegen path — reuse buffers across compilations
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
- [ ] Consolidate `cli/types.zig` — 16+ flags scattered across parse modules could use a FlagRegistry pattern
- [ ] Improve reverse engineering confidence scores — currently binary (high/low), could be granular
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
| 6: Ecosystem & Community | 🔲 Planned | 0/9 | 9 |
| 7: Editor Extensions | 🔲 Planned | 0/10 | 10 |
| 8: Language Evolution | 🔲 Planned | 0/8 | 8 |
| Architecture Targets | 🟡 Ongoing | 12/14 | 2 |
| Technical Debt | 🔲 Planned | 0/5 | 5 |
| **Total** | | **71/105** | **34** |

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
