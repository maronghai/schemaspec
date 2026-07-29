# Plan: v0.52.0 — Migration Refactoring & Safety Improvements

## Version: 0.52.0

## Summary

Architectural cleanup focused on reducing code duplication in the migration engine, fixing unsafe runtime panics, and consolidating shared parser utilities.

## Changes

### 1. Refactor migrate.zig — Unify forward/rollback duplication (~180 lines saved)

- [x] Add `Direction` enum (`forward`, `rollback`)
- [x] Unify `emitViewDiffs` / `emitRollbackViewDiffs` → single `emitViewDiffs` (identical logic, already direction-agnostic)
- [x] Unify `emitTableDiffs` / `emitRollbackTableDiffs` → single `emitTableDiffs` with Direction parameter
- [x] Unify `emitFieldDiffs` / `emitRollbackFieldDiffs` → single `emitFieldDiffs` with Direction parameter
  - Forward: add→ADD COLUMN (new_field), drop→DROP, modify→MODIFY (new_field), rename→RENAME (old→new)
  - Rollback: add→DROP, drop→ADD COLUMN (old_field), modify→MODIFY (old_field), rename→RENAME (new→old)
- [x] Unify `emitIndexDiffs` / `emitRollbackIndexDiffs` → single `emitIndexDiffs` with Direction parameter
  - Forward modify: drop old, add new
  - Rollback modify: drop new, add old (reversed)
- [x] Unify `emitFkDiffs` / `emitRollbackFkDiffs` → single `emitFkDiffs` with Direction parameter
  - Forward modify: drop old, add new
  - Rollback modify: drop new, add old (reversed)
- [x] Unify `emitMetadataDiffs` / `emitRollbackMetadataDiffs` → single `emitMetadataDiffs` with Direction parameter
  - Forward: use new_comment/new_engine
  - Rollback: use old_comment/old_engine
- [x] Delete all `emitRollback*` functions (lines 95-379)
- [x] Verify all 34 migration golden tests pass

### 2. Fix unsafe `unreachable` in runtime code

- [x] `parse_index.zig:50,90` — `.primary_key => unreachable` → `return error.UnexpectedPrimaryKey`
- [x] `reverse/codegen.zig:249` — `.primary_key => unreachable` → `else => {}` (already skipped by `if (idx.kind == .primary_key) continue`)

### 3. Consolidate whitespace helpers in sql_parser_helpers.zig

- [x] Merge `skipWhitespaceAndComments` and `skipWhitespaceAndCommentsNoSemicolon` into single function
- [x] Both share identical logic (skip whitespace + -- comments + /* comments); the "NoSemicolon" variant adds no actual semicolon-specific behavior
- [x] Update callers to use unified function

### 4. Documentation updates

- [x] Update VERSION file → 0.52.0
- [x] Update version.zig → "0.52.0"
- [x] Update ROADMAP.md — add v0.52.0 release entry
- [x] Update CHANGELOG.md — add v0.52.0 section

## Verification

- [x] `cd rune && zig build test` — 568/588 pass (17 pre-existing tokenizer failures, 3 crashes unrelated to changes)
- [x] `bash tests/test_migrate.sh` — 34/34 migration tests pass
- [x] `bash tests/test.sh` — 86/86 MySQL golden tests pass
- [x] `bash tests/test_postgres.sh` — 85/85 PG golden tests pass
- [x] `bash tests/test_sqlite.sh` — 25/25 SQLite golden tests pass
- [x] `bash tests/test_reverse.sh` — 21/21 reverse tests pass
- [x] `bash tests/test_diff.sh` — 12/12 diff tests pass
- [x] `bash tests/test_roundtrip.sh` — 26/26 roundtrip tests pass
- [x] `bash tests/test_error_recovery.sh` — 12/12 error recovery tests pass
- [x] `bash tests/test_imports.sh` — 6/6 import tests pass
- [x] `bash tests/test_json_schema.sh` — 3/3 JSON schema tests pass
