# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.324.0 (2026-08-22) — 70,900+ lines of Zig (46,300+ production + 24,500+ tests across 330 `.zig` files), 2,036 unit tests, 85 lint rules, 112 `REVERSE_MAP` entries, 37 golden test suites, 12 generators × 6 dialects.

> This roadmap was restructured on 2026-08-21: all thirteen completed phases are condensed into a summary, and every remaining open item is consolidated under Phase 14 (each item now appears exactly once). Historical detail lives in [CHANGELOG.md](CHANGELOG.md) and git history.
>
> **Version-drift reconciliation (2026-08-21):** commit 0.316.0 had bumped the tree's `VERSION` straight to 0.320.0 while git HEAD remained "0.318.0", and no 0.319/0.320 commits exist. All version strings now read **0.318.0** (matching HEAD), and [CHANGELOG.md](CHANGELOG.md) has backfilled entries for v0.313.0–v0.318.0 reconstructed from git history. The next feature release should be **0.319.0** (see [plans/plan-0.319.0.md](plans/plan-0.319.0.md)). *(Reconciled as planned: v0.319.0 shipped template overrides, v0.320.0 shipped composite types — see [plans/plan-0.320.0.md](plans/plan-0.320.0.md).)*

---

## Legend

- [x] Done — shipped in a release
- [ ] Planned — not yet started
- [~] In progress — partial implementation exists
- Priority is top-down within each section; sections overlap in practice
- Version numbers are approximate — shipped when ready, not by deadline

---

## Completed Work (Phases 1–13)

Phases 1–13 are complete: **144 of 151 tracked items shipped** through v0.318.0. What each phase delivered:

### Phase 1: Core Solidification ✅ (v0.38–v0.81)

Parser, semantic analysis, and testing infrastructure: multi-error recovery, partial schema compilation, cycle detection, FK validation, template warnings, duplicate column detection, Levenshtein suggestions, fuzz testing, golden test parallelization, property-based roundtrip tests.

### Phase 2: Extended Dialect Support ✅ (v0.48–v0.76)

All 6 SQL dialect backends (MySQL, PostgreSQL, SQLite, MSSQL, Oracle, Db2) behind the DialectBackend vtable (32 function pointers + behavioral flags), dialect-specific golden suites (470+ tests), dialect-aware reverse engineering, auto-detection, shared reverse mapping data (112 entries).

### Phase 3: ORM & API Schema Output ✅ (v0.48–v0.88)

Prisma, Drizzle, TypeORM, SQLAlchemy, Knex generators; OpenAPI 3.1, GraphQL SDL, JSON Schema, symbol-index output; pluggable generator registry, shared test helpers, ORM default formatter.

### Phase 4: Incremental & Live Workflows ✅ (v0.93–v0.139)

Incremental migration, dependency graph, `rune migrate status`, `rune watch`, live database diff, schema drift detection, GitHub Action, GitLab CI template, pre-commit hook generator.

### Phase 5: Developer Experience (LSP) ✅ (v0.144–v0.146)

LSP server with JSON-RPC 2.0, document sync, real-time diagnostics, completion, hover, go-to-definition, document symbols, code actions, document formatting. WASM cross-compilation, Windows native builds, ARM64 CI.

### Phase 6: Ecosystem & Community ✅ (9/11 — 2 items carried to Phase 14)

Package managers (brew/scoop/apt/yum), npm package, Docker image, Zig package manager; migration guide, cookbook, video walkthroughs; RFC process, schema registry (`rune registry`, v0.311.0). *Interactive tutorial and playground sharing remain open — see Phase 14.*

### Phase 7: Editor Extensions ✅ (13/13)

VS Code extension (TextMate grammar, IntelliSense, diagnostics, rename with FK updates, rich hover, inlay hints); Neovim plugin (lspconfig, Treesitter grammar, keybindings); JetBrains IDE plugin (completion, inspections, quick-fixes, LSP integration).

### Phase 8: Language Evolution ◧ (4/9 — 5 items carried to Phase 14)

Shipped: `@version` schema versioning (v0.237.0), `@if(dialect=)` conditional blocks (v0.191.0), `+` doc directive (v0.199.0), dialect-aware SQL formatting (v0.250.0), Mermaid ER diagrams in docs generator (v0.191.0). *Generator plugins, template overrides, marketplace, composite types, and live collaboration remain open — see Phase 14.*

### Phase 9: Extensibility & Plugin Foundation ✅ (2/2)

Pydantic v2 generator exercising the open-closed registry (v0.282.0); comptime registry collision guard.

### Phase 10: Lint Rule Hardening & Symmetry ✅ (12/12, v0.288–v0.297)

Closed the auto-increment, referential-integrity, default-value-correctness, and view-quality rule families, and completed the full (PK, FK, UNIQUE) × (regular, unique) index-redundancy symmetry grid.

### Phase 12: Cross-Dialect Portability Linting ✅ (5/5, v0.298–v0.310)

`unindexable-type-indexed`, `unsigned-overflow-risk`, `charset-collation-portability`, `decimal-precision-portability`, `auto-increment-dialect-gap` — catching schemas that compile in one dialect but break or silently degrade in another.

### Phase 13: Documentation & Spec Completeness ✅ (3/3, v0.301–v0.302)

`@version` directive documented in all three spec files; ARCHITECTURE.md metric re-verification; single-source-of-truth coverage matrix ([docs/coverage-matrix.md](docs/coverage-matrix.md)).

### Phase 11: Ecosystem & CI Completion ✅ (tracking phase — closed)

Was a consolidated tracker for open items from Phases 6–8. Its done items (video walkthroughs, schema registry, JetBrains plugin ×2, CI optimization below 5 minutes via 4-shard matrix, v0.307.0) are recorded under their origin phases above; its open items moved to Phase 14. No unique items.

### Architecture Targets ✅ (22/22)

Performance: streaming compilation, parallel table compilation, mmap I/O, zero-allocation BufferPool codegen, incremental compilation with disk-persisted cache, benchmark regression CI gate (>10% fails). Code quality: zero `catch unreachable` / unsafe casts in production code, named constants, IR versioning, memory-leak audits, fuzz expansion, graceful OOM/filesystem error recovery. Platform: WASM, Windows native, ARM64 CI, FreeBSD CI, CI matrix sharding (<5 min).

### Technical Debt ✅ (15/15)

All tracked refactors shipped: generator deduplication, FlagRegistry, granular reverse confidence, standardized error format/output/I/O/handler params, table-driven LSP dispatch, data-driven lint dispatch, config-merge/error-handling extraction, shared SQL type renderer, lint fixer decomposition, SARIF metadata deduplication.

---

## Phase 14: Ecosystem Maturation (Current Focus) 🔲

Every remaining roadmap item is consolidated here — large, IR/pipeline-stage-level features (not registry-entry extensions), each scoped as its own RFC + release. **Status: 5 of 7 done (plugin API stub, template overrides, composite types, interactive tutorial, playground sharing), 2 remaining (WASM plugin runtime needs an embedded interpreter; live collaboration is exploratory).**

### Generator Plugin System

- [~] User-defined generators via Zig plugins or WASM modules (from Phase 8) — API stub implemented in `wasm/plugin.zig` (v0.316.0: `loadWasmPlugins`, `loadWasmPlugin`, plugin-aware `getGenerator`/`listAllGenerators`; returns NotImplemented — Zig 0.16 std has no WASM runtime). Full implementation requires embedding a runtime (wasmtime, wasmer, or custom interpreter).
- [x] Template overrides — `.rune-template` files for customizing generator output (from Phase 8) — shipped v0.319.0: `generators/template_override.zig` discovers `<generator>.rune-template` in `--template-dir` > `./.rune/templates/` > `~/.rune/templates/`; `{{SCHEMA_NAME}}`/`{{DIALECT}}`/`{{VERSION}}`/`{{GENERATOR}}` placeholders + `{{#TABLES}}...{{TABLE_NAME}}...{{/TABLES}}` loop; no template → built-in output byte-identical.
- [ ] Generator marketplace — community-contributed generators (from Phase 8), building on the schema registry foundation (v0.311.0).

### Distribution & Community

- [x] Interactive tutorial — web-based walkthrough with live examples (from Phase 6) — shipped v0.322.0 + v0.323.0: working `rune.wasm` build (`entry=.disabled` + `-rdynamic`), rewritten browser/Deno `wasm/rune.js`, and all 33 compilable tutorial snippets wired with Open-in-Playground links (hash-preload verified end-to-end).
- [x] Playground sharing — share `.ss` snippets via URL (from Phase 6) — shipped v0.322.0 + v0.324.0: playground shell ([playground/index.html](playground/index.html)) with editor + SQL/Lint/Docs tabs, dialect switcher, and `#<base64url>` share links (same format as `rune share`); GitHub Pages deployment workflow (`.github/workflows/pages.yml`) builds rune.wasm on push to main and publishes with the repo-relative layout intact. One-time repo enablement: Settings -> Pages -> Source: GitHub Actions.

### Advanced Schema Features

- [x] Composite types — reusable field groupings beyond templates (from Phase 8) — shipped v0.320.0: top-level declaration (`* name`) + in-place embedding inside table bodies (`*name`); new `resolve_composites` semantic pass (18th) expands embeds between `resolve_conditionals` and `autofk`; errors on unknown/duplicate/empty, warns on unused; see [schemaspec/schema.md §11](schemaspec/schema.md#11-composite-types) and [plans/plan-0.320.0.md](plans/plan-0.320.0.md).
- [ ] Live collaboration — multi-user schema editing via LSP extensions (from Phase 8).

---

## Maintenance & Release Hygiene

Process debt observed during the 2026-08-21 roadmap audit:

- [x] Backfill [CHANGELOG.md](CHANGELOG.md) for v0.313.0–v0.318.0 — entries reconstructed from git history (2026-08-21). No v0.319/v0.320 commits exist; the tree's `VERSION` had been bumped to 0.320.0 inside commit 0.316.0.
- [x] Version alignment — all version strings (`VERSION`, `rune/VERSION`, `rune/build.zig.zon`, npm/scoop/homebrew/vscode manifests) now read **0.318.0**, matching git HEAD (fixed 2026-08-21).
- [x] Commit-title typo (2026-08-22) — the v0.323.0 commit was amended with title "0.333.0" while every tree version string correctly read 0.323.0; content unaffected, recorded here rather than rewriting history.
- [x] Commit-message / version alignment — v0.320.1 shipped with a bare-number title while `VERSION` still read 0.320.0 (the amend renamed the test-infra commit but not the tree); CHANGELOG backfilled for 0.320.0/0.320.1 and all strings aligned to **0.321.0** (2026-08-22). Descriptive titles from this release onward.
- [x] Golden-test runner parity — `zig build golden-tests` runs the full coverage runner (`test_coverage.sh --fast --serial`, all 37 suites); Windows-native environments still need bash for the suites themselves, but one entry point now covers everything CI covers.

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1: Core Solidification | ✅ Complete | 9/9 | 0 |
| 2: Extended Dialect Support | ✅ Complete | 14/14 | 0 |
| 3: ORM & API Schema Output | ✅ Complete | 13/13 | 0 |
| 4: Incremental & Live Workflows | ✅ Complete | 10/10 | 0 |
| 5: Developer Experience (LSP) | ✅ Complete | 13/13 | 0 |
| 6: Ecosystem & Community | ◧ Carried to 14 | 9/11 | 2 |
| 7: Editor Extensions | ✅ Complete | 13/13 | 0 |
| 8: Language Evolution | ◧ Carried to 14 | 4/9 | 5 |
| 9: Extensibility & Plugin Foundation | ✅ Complete | 2/2 | 0 |
| 10: Lint Rule Hardening & Symmetry | ✅ Complete | 12/12 | 0 |
| 11: Ecosystem & CI Completion | ✅ Closed (tracker) | — | — |
| 12: Cross-Dialect Portability Linting | ✅ Complete | 5/5 | 0 |
| 13: Documentation & Spec Completeness | ✅ Complete | 3/3 | 0 |
| 14: Ecosystem Maturation | 🔲 Current focus | 5/7 | 2 |
| Architecture Targets | ✅ Complete | 22/22 | 0 |
| Technical Debt | ✅ Complete | 15/15 | 0 |
| Maintenance & Release Hygiene | ◧ In progress | 2/4 | 2 |
| **Total** | | **150/155** | **5** |

*Counting note: Phases 6/8 open items are listed once, under Phase 14; the former summary's "143/149" under-counted Phase 6 (listed 11/11 while 2 items were open).*

---

## Roadmap by Quarter

### 2026 Q3 (Jul–Sep) — current

~~Template overrides~~ shipped in v0.319.0; ~~composite types~~ shipped in v0.320.0 (see [plans/plan-0.320.0.md](plans/plan-0.320.0.md)). **Release hygiene**: CHANGELOG backfilled and version strings aligned to HEAD (done 2026-08-21); descriptive commit messages adopted from v0.320.0 onward.

### 2026 Q4 (Oct–Dec)

**WASM plugin runtime** — embed a runtime behind the v0.316.0 stub so user-defined generators actually execute. **Interactive tutorial + playground sharing** — web experience on the existing WASM library.

### 2027 Q1 (Jan–Mar)

**Composite types**, **generator marketplace** (on the registry + override foundations), **live collaboration** exploration via LSP.

---

## Release History

For detailed per-version release notes, see [CHANGELOG.md](CHANGELOG.md) (168 entries, v0.6.6 → v0.318.0; the v0.313.0–v0.318.0 entries were backfilled on 2026-08-21 from git history).
