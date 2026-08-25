# Rune Roadmap

A single `.ss` file is the source of truth that generates SQL DDL for any dialect, migration scripts, ORM schemas, API validation rules, and documentation.

**Current version**: 0.336.0 (2026-08-26) — ~75,000 lines of Zig (~49,000 production + ~25,500 tests across 334+ `.zig` files), 2,122 unit tests, 86 lint rules, 112 `REVERSE_MAP` entries, 44 golden inputs (36 runner-covered suites), 12 generators × 6 dialects.

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
- [x] Composite embed × index-bearing feature audit (v0.325.0) — deep analysis found the v0.321.0 index-remap fix covered conditional blocks but missed composite embeds: three repro'd bugs (@if wrapping an embed line was ignored; template merge and conditional strip both left `insert_pos` stale). Fixed via parser dialect stamping + two remap passes; the position invariant is now documented in `types/ast.zig` and [schemaspec/schema.md §11](schemaspec/schema.md#11-composite-types).
- [x] Lint auto-increment false positives on datetime defaults (v0.326.0) — the ubiquitous audit-field pattern (`created_at t+` / `updated_at t++`, meaning DEFAULT CURRENT_TIMESTAMP) tripped four auto-increment rules and made `--strict` CI gates fail on valid schemas; `--fix` also appended redundant explicit defaults. Rules now gate through a shared `hasIdentityModifier` predicate; genuine misuses (`s++`, double `n++`) still reported.
- [x] Golden-test runner parity — `zig build golden-tests` runs the full coverage runner (`test_coverage.sh --fast --serial`, all 37 suites); Windows-native environments still need bash for the suites themselves, but one entry point now covers everything CI covers.
- [x] Monorepo sub-project boundaries (v0.327.0) — language spec deduplicated to a single source of truth in `schemaspec/` (stale snapshots under `rune/` removed; three spec errors corrected against golden-test evidence), five sub-project boundaries documented in CLAUDE.md with change-impact matrix, wasm export contract documented ([docs/wasm-api.md](docs/wasm-api.md)), and version propagation scripted (`scripts/sync-version.sh --check`, wired into CI).
- [x] CLI consistency audit + fixes (v0.328.0)
- [x] Source-rewriting tools vs brace syntax (v0.329.0)
- [x] Brace-form table syntax formalized (v0.330.0)
- [x] LSP long-session memory + watch polling efficiency (v0.331.0)
- [x] Reverse pipeline inline column-level FK (v0.332.0) — `a_id INT REFERENCES users(id) ON DELETE CASCADE` (the dominant mysqldump/SQLite .schema style) was silently dropped by the SQL parser and its action fragments leaked in as ghost fields; now captured on the column and emitted alongside table-level constraints with correct bare-reference/default-action handling (reverse suite 21 → 24).
- [x] Cross-layer consistency defects (v0.333.0) — deep audit of diff/migrate × generators × lint found five silent-corruption bugs, all repro'd on the main path: `lint --fix` (and therefore `rune migrate`, which auto-lints) rewrote schemas with unparseable defaults (` = 0` — tokenizer splits it, default silently dropped; timestamps appended without a trailing newline fused the next table header into a field line); the diff engine never saw inline column-level FKs (codegen merges `Field.fk`, diff compared only table-level fks → adding `user_id > users.id` produced an empty migration); compound FKs dropped every reference column after the first dot-token (mismatched FOREIGN KEY column counts; prisma emitted `[fields[0]]`); rename detection could point two CHANGE COLUMNs at one added field; the incremental cache hashed SqlType tags without payloads (`varchar(50)` ≡ `varchar(255)` under `--cache`). Also fixed quoted-default double-wrapping (`='x'` → `DEFAULT ''x''`) and case-sensitive keyword matching that quoted `=false`. knex/drizzle/prisma now carry decimal precision/scale. Compound-FK goldens added; unit tests 2094 → 2100.
- [x] Windows-native `test_migrate_status.sh` null-byte failures — RESOLVED in v0.334.0: not an output-encoding issue at all. `collectMigrateFiles` duplicated only `.name` while `.seq`/`.label` pointed into the directory iterator's reused buffer, so every label printed as NUL-filled garbage on any platform (Linux arenas merely hid it). Suite 2/7 → 7/7.
- [x] LSP root-cause + three-subsystem audit fixes (v0.334.0) — three parallel deep audits (LSP features, generator fidelity, watch/stream/cache/import lifecycles) confirmed ~40 defects, all fixed and verified: the LSP fed the whole document to the tokenizer as one line so every AST-based feature (hover/goto/references/symbols/completion context/rename prep) was dead on real schemas; parse diagnostics collapsed to a single vague marker; references/highlights compared columns against table lines; rename emitted overlapping duplicate edits and ignored Rune's `>` FK syntax; `--stream --cache` served freed memory on hits; diamond imports were rejected as circular (recursion-stack cycle detection now); parallel error paths duplicated tables; imported-file errors didn't propagate to exit codes (`--check` gate bypass); share formatted through a dead stack frame; cache hashes missed comments/docs/ss_symbol; watch leaked its arena per poll and warned about deleted files forever; streaming/parallel dropped `$ mydb`/`@version` headers. Generator side: knex/sqlalchemy dropped FK columns entirely; drizzle emitted uncompilable TS four ways (`//` inside array literals, `#` comments in object literals, bare composite-FK identifiers, pg `.autoincrement()`); typeorm lost non-autoincrement PKs; graphql mutations referenced undeclared PascalCase types and duplicated same-target relation fields; prisma forced enum defaults to the first value and left string defaults unquoted; referential actions (-C/-N) dropped by all four ORM generators; `t+` columns wrongly marked required by openapi/json-schema; compound FKs truncated to first column in docs; unescaped quotes broke symbol-index JSON. Also CLI honesty: `-f` registered for `--format`, `diff --summary` separator fixed per help text, unsupported flag combos error instead of silently ignoring, table-header comment colon stripped at parse time. Unit tests 2100 → 2111; coverage runner 36/36; bench gate clean.
- [x] Reverse-engineering pipeline audit + forward parse gaps (v0.335.0) — first deep audit of the reverse subsystem (dialect detection, SQL parser, reverse codegen) found 11 verified defects, all repro'd on the main path and fixed: dialect auto-detection matched keywords as raw substrings (`-- RESTRICT` comment flipped MySQL dumps to SQLite, dropping inline KEY indexes); `reverse --format json` emitted invalid JSON (trailing/missing commas); `diff --format sarif` broke on any FK modify (string closed early, suffix appended outside it); SQL keyword matching was case-sensitive so lowercase dumps parsed `primary key` as phantom columns or failed outright; `ALTER TABLE ADD COLUMN` was silently dropped by reverse. Forward gaps that broke roundtrips: `=NOW()` compiled to `DEFAULT 'NOW' CHECK ()`; reverse passthrough `CHAR(2)` recompiled as `CHAR` + fabricated CHECK; a UTF-8 BOM silently voided the whole schema (exit 0, zero tables — Windows editors emit BOM by default); spaced/quoted identifiers corrupted across the roundtrip. Migrate/lint boundaries: no-timestamps fixer injected audit fields after trailing views (every migrate then warned per line); default fixers appended into inline comments producing COMMENT 'the name =0'; migrate left `.lint-fixed.ss` litter per run; `--graph` reported false cycles for shared-table histories. Repo hygiene: stale `rune/ROADMAP.md`, `rune/CHANGELOG.md`, `rune/plans/`, and a 5.8 MB binary blob committed as `rune/tests` in v0.191.0 removed. Unit tests 2111 → 2117; coverage runner 36/36; bench gate clean.
- [x] Four-way deep audit: emitters × parser boundaries × semantic interactions × rewriting tools (v0.336.0) — parallel audits of the four remaining never-deeply-audited subsystems confirmed ~28 defects, all repro'd and fixed: the global `--format` flag was consumed but never forwarded (`lint --format sarif` emitted plain text; export defaulted to text against its own help); every JSON emitter (export/json-schema/openapi/symbol-index/stats) interpolated names raw, so quotes in table/column/enum values produced invalid JSON; apostrophes in comments broke MySQL/PG/Oracle/Db2 COMMENT statements (single quotes now doubled); docs Markdown/Mermaid broke on pipes/spaced names; bare inline FKs emitted `FOREIGN KEY () REFERENCES ` `()`; enum values with spaces shattered; typo'd template refs inherited zero fields silently (exit 0); typedef enum bases lost values; descending indexes were parsed by three layers but ignored at emission; parenthesized free-form CHECK mangled; imported composites vanished (unknown composite after any import); compound-FK type checks aborted after the first pair; autofk/suffix_inference dropped template_ref (conflict pass permanently dead); composite-embed name collisions duplicated columns; duplicate fields inside one template body both reached DDL; view FROM scanner false-warned on tabs/subqueries; formatter renamed fields inside @if blocks, tune dropped the preamble ($/@version/~), deleted member-table indexes, picked conflicting field variants from hash order; `init --output x.ss` created x.ss.ss with templates failing format --check. Unit tests 2117 → 2122; coverage runner 36/36; bench gate clean.

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
| Maintenance & Release Hygiene | ✅ Complete (13/13) | 13/13 | 0 |
| **Total** | | **161/161** | **0** |

*Counting note: Phases 6/8 open items are listed once, under Phase 14; the former summary's "143/149" under-counted Phase 6 (listed 11/11 while 2 items were open).*

---

## Roadmap by Quarter

### 2026 Q3 (Jul–Sep) — current

~~Template overrides~~ shipped in v0.319.0; ~~composite types~~ shipped in v0.320.0 (see [plans/plan-0.320.0.md](plans/plan-0.320.0.md)). **Release hygiene**: CHANGELOG backfilled and version strings aligned to HEAD (done 2026-08-21); descriptive commit messages adopted from v0.320.0 onward; CLI consistency audit shipped in v0.328.0 (help/flag/output-channel/bench-gate fixes, see Maintenance section).

### 2026 Q4 (Oct–Dec)

**WASM plugin runtime** — embed a runtime behind the v0.316.0 stub so user-defined generators actually execute. **Interactive tutorial + playground sharing** — web experience on the existing WASM library.

### 2027 Q1 (Jan–Mar)

**Composite types**, **generator marketplace** (on the registry + override foundations), **live collaboration** exploration via LSP.

---

## Release History

For detailed per-version release notes, see [CHANGELOG.md](CHANGELOG.md) (168 entries, v0.6.6 → v0.318.0; the v0.313.0–v0.318.0 entries were backfilled on 2026-08-21 from git history).
