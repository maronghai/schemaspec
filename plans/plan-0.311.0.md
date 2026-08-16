# Upgrade Plan: v0.311.0

**Current Version**: 0.310.0
**Target Version**: 0.311.0 (minor increment for the Phase 6 Schema Registry foundation + documentation/ROADMAP sync)
**Date**: 2026-08-16

---

## Version Calculation

| Current | Increment | Reason |
|---------|-----------|--------|
| 0.310.0 | minor → 0.311.0 | Phase 6 Schema Registry foundation (local shared template library CLI): `rune registry init/add/list/show/remove`. No breaking changes; extends the CLI only. |

---

## Scope Decision

The previous planning session opened v0.311.0 with a 30+ hour plan (Schema Registry + WASM Generator Plugin
system + broad doc sweep). That scope is not completable in one pass and most of it was never started. This
plan narrows v0.311.0 to the **achievable, verifiable** Schema Registry foundation plus the required
documentation/version/ROADMAP synchronization, and defers the rest:

- **Deferred to v0.312.0+**: `@import "registry:<name>"` resolution integration, WASM Generator Plugin system,
  template overrides, generator marketplace, composite types, live collaboration, interactive tutorial,
  playground sharing.

---

## Focus Areas

1. **Phase 6: Ecosystem & Community** — Schema Registry foundation (local shared template library CLI)
2. **Documentation & Spec Sync** — document the new `registry` subcommand and module
3. **Version Synchronization** — VERSION, build.zig.zon, rune/VERSION, packaging manifests
4. **ROADMAP / CHANGELOG** — progress markers + release notes
5. **Testing & Benchmarking** — full validation
6. **Local Deploy** — upx-compressed binary to /mnt/d/zbin/rune

---

## Detailed Plan

### Phase 6: Ecosystem & Community — Schema Registry Foundation

- [x] **6.1 `rune registry` CLI subcommand group** — `cli/registry_cmd.zig` implements `init`, `add <name> <path>`,
  `list`, `show <name>`, `remove <name>`. Wired through `cli/types.zig` (`Command.registry`), `cli/parse_utils.zig`
  (`parseRegistryArgs`), `cli/parse.zig` (parser table), and `main.zig` (`dispatch`).
- [x] **6.2 Fix `registry show` output** — the handler previously passed format strings with `null` args to
  `writeOutput` (which expects a plain string), printing literal `{s}`/`{any}`. Now interpolates metadata fields
  (name, version, description, author, tags, dependencies, min_rune, created/updated, content).
- [x] **6.3 Fix directory iteration close panic** — `list` opened the templates dir without `.iterate = true`
  and then double-closed it, panicking under Zig 0.16 threaded `std.Io`. Now opens with
  `openDir(io, path, .{ .iterate = true })` and a single `defer dir.close(io)`.
- [x] **6.4 Non-zero exit on error paths** — `show`/`remove`/unknown-subcommand/before-init now `return` a distinct
  error so the process exits 1 and `cli_errors.handleDispatchError` prints it.
- [x] **6.5 Functional test suite** — `tests/test_registry.sh` (10 cases, temp-HOME isolated) wired into
  `tests/test_coverage.sh`. Validates the full init→add→list→show→remove lifecycle and error behavior.

### Documentation & Spec Sync

- [x] **13.1 `CLAUDE.md`** — add `rune registry ...` to Quick Usage; add `cli/registry_cmd.zig` to Source Layout;
  note the registry CLI in the Schema Registry context.
- [x] **13.2 `rune/ARCHITECTURE.md`** — add a Schema Registry section / `cli/registry_cmd.zig` module entry; bump
  file-count metric (327 → 328) and note the new CLI surface.
- [x] **13.3 `README.md` / `rune/README.md`** — mention Schema Registry in features/usage.
- [x] **13.4 `docs/coverage-matrix.md`** (skipped — registry is not a generator; matrix unchanged) — no generator/dialect change; verify it still derives from `REGISTRY`
  (no edit required unless a generator was added). *Skipped* (registry is not a generator).

> Note: `rune/schema.md`, `rune/type.md`, `rune/grammar.ebnf` are **not** changed — the registry is a CLI feature,
> not a language construct. The `@import "registry:<name>"` syntax is deferred to v0.312.0, so the grammar is
> unchanged.

### Version Synchronization

- [x] **14.1** Bump version strings: `VERSION`, `rune/VERSION`, `rune/build.zig.zon` (`.version`), and packaging
  manifests (`packaging/npm/package.json`, `packaging/scoop/rune.json`, `packaging/homebrew/rune.rb`,
  `packaging/vscode/package.json`) 0.310.0/0.306.0 → 0.311.0.

### ROADMAP / CHANGELOG

- [x] **15.1 `ROADMAP.md`** — update "Current version" header (0.311.0, 2026-08-16); mark Phase 6 "Schema registry —
  shared template library" as done (v0.311.0); mark the Phase 11 cross-reference item done; update the summary
  table (Phase 6 → 11/11, total done/remaining).
- [x] **15.2 `CHANGELOG.md`** — add a v0.311.0 release entry.

### Testing & Benchmarking

- [x] **16.1** `zig build test` — unit tests pass (2022+).
- [x] **16.2** Golden/functional suites — `bash tests/test_registry.sh` (10/10) and a representative golden run
  (`bash tests/test.sh` MySQL) to confirm no regression.
- [x] **16.3** `zig build bench` and `zig build bench -- --check` — no >10% regression.

### Local Deploy

- [x] **17.1** `zig build --release=small --prefix-exe-dir upx`, `upx -9 --lzma zig-out/upx/rune`, copy to
  `/mnt/d/zbin/rune`.

---

## Effort Summary

| Category | Estimated Hours |
|----------|-----------------|
| Phase 6 (Schema Registry CLI + fix + tests) | 3.0 (done) |
| Documentation Sync | 1.5 |
| Version Synchronization | 0.3 |
| ROADMAP / CHANGELOG | 0.5 |
| Testing & Benchmarks | 0.5 (partially automated) |
| Local Deploy | 0.2 |
| **Total Estimated** | **~6.0 hours** |

---

## Deferred to v0.312.0+

- `@import "registry:<name>"` resolution integration (import resolver extension)
- WASM Generator Plugin system (host infrastructure + registry integration + example plugin)
- Template overrides (`.rune-template` files)
- Generator marketplace
- Composite types
- Live collaboration
- Interactive tutorial / playground sharing

---

## Acceptance Criteria

- [x] `rune registry init/add/list/show/remove` functional (verified by `tests/test_registry.sh`)
- [x] Error paths exit non-zero
- [x] All unit tests pass (`zig build test`)
- [x] No golden-suite regression
- [x] Benchmark check passes (no >10% regression)
- [x] VERSION + build.zig.zon + rune/VERSION + packaging manifests at 0.311.0
- [x] ROADMAP.md + CHANGELOG.md updated
- [x] Binary deployed to /mnt/d/zbin/rune
