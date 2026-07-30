# Plan: v0.55.0 — Parser Fixes & Memory Safety

## Scope

Fix compound FK parsing, eliminate test memory leaks, improve error handling safety.

## Version: 0.55.0

---

## Tasks

### 1. Fix compound FK parsing (parse_fk.zig)

- [x] Split multi-dot references on ALL dots (e.g. `projects.org_id.project_id` → table `projects`, fields `["org_id", "project_id"]`)
- [x] Collect all tokens before the first dot-containing token as local fields (compound local fields)
- [x] Extract `parseDottedRef` helper function for clean dot splitting with trailing-dot fallback
- [x] Fix use-after-free: move `alloc.free(f)` calls outside iteration loops
- [x] Fix missing `alloc.dupe` for `local_field_name` in shorthand-no-dot branch

### 2. Fix parse_fk_test.zig memory leaks

- [x] Add `freeFk` helper that frees all inner strings before outer slices
- [x] All 9 FK tests now pass with zero leaks

### 3. Add DiagnosticCollector overflow test

- [x] Test that `push` stops recording errors after `max_errors` limit
- [x] Test that warnings don't count toward `max_errors`

### 4. Update version

- [x] VERSION → 0.55.0
- [x] version.zig → "0.55.0"

### 5. Update docs

- [x] ROADMAP.md: update version header
- [x] CLAUDE.md: no changes needed (test counts are stable)

### 6. Fix `catch return` in semantic passes

- [ ] Deferred to next release — current pattern is acceptable for CLI tool (graceful degradation)

### 7. Add import recursion depth test

- [ ] Deferred to next release

---

## Test Results

- **Before**: 593 pass, 14 fail, 3 crash (610 total); 532 leaks
- **After**: 598 pass, 13 fail, 3 crash (614 total); 525 leaks
- **FK tests**: 6 failing → 0 failing (all pass)
- **New tests**: +4 (compound ultra, single-local-compound-ref, 2x DiagnosticCollector overflow)
- **Remaining failures**: pre-existing leaks in parse_index/parse_table tests + locFromLine assertion
