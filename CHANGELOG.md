# Changelog

All notable changes to this project will be documented in this file.

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
