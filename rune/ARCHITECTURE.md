# Rune Architecture

> Internal architecture documentation for contributors.

## Overview

Rune is a compiler that transforms `.ss` schema files into SQL DDL. It consists of three independent pipelines:

1. **Forward pipeline**: `.ss` → SQL DDL (CREATE TABLE, indexes, FKs)
2. **Reverse pipeline**: SQL DDL → `.ss` schema
3. **Diff/Migrate**: compare two schemas and generate migration SQL

## Module Dependency Graph

```
                    main.zig (entry + orchestration)
                   ╱    │    ╲         ╲
                  ╱     │     ╲         ╲
           ┌─────┐  ┌──┴───┐  ┌───────┐  ┌────────┐
           │codegen│ │migrate│ │reverse_│  │sql_parser│
           └──┬──┘ └──┬──┘  └──┬────┘  └──┬─────┘
              │        │        │           │
        ┌─────┘   ┌────┘    ┌───┘      ┌───┘
        ▼         ▼         ▼          ▼
   ┌─────────┐ ┌──────┐ ┌────────┐ ┌───────┐
   │typed_ast │ │ diff │ │reverse_│ │ ast   │
   └────┬────┘ └──────┘ │ map    │ └───┬───┘
        │                └────────┘     │
        ▼                 ╲    ╱        ▼
   ┌─────────┐     ┌───────────┐  ┌──────────┐
   │ sql_type │     │diagnostic │  │ template │
   └────┬────┘     └───────────┘  └──────────┘
        │                               │
        ▼                          ┌────┘
   ┌──────────┐                    ▼
   │type_reg  │              ┌──────────┐
   └──────────┘              │ semantic │
                             └──────────┘
```

**Leaf modules** (zero internal dependencies): `ast.zig`, `dialect/enum.zig`, `diagnostic/format.zig`, `color.zig`

**Key modules**:
- `sql_type.zig`: `SqlType` union with `toSql()` delegating to `DialectBackend.renderType`. Variants: int, bigint, smallint, decimal, varchar, text, blob, json, jsonb, datetime, date, timestamptz, boolean, uuid, inet, serial, enum_values, raw_sql, passthrough. `toJsonSchema()` for JSON Schema output.
- `type_registry.zig`: SS symbol → `SqlType` mapping (`lookupCustomType`, `lookupSqlTypeDirect`), reverse lookup, and symbol classification helpers (`isNumericSymType`, `isDatetimeSymType`). 17 core SS symbols: n, N, i, m, M, s, S, b, B, j, J, I, d, t, T, U, p
- `types/reverse_map.zig`: Shared `REVERSE_MAP` data (112 entries) + `ReverseMapping` struct with `DialectTypeMap` for dialect-indexed type strings. Canonical location consumed by both `reverse/map.zig` and `diff/semantic.zig`.

- `cli/registry_cmd.zig`: **Schema Registry CLI** (`rune registry init/add/list/show/remove`). Stores templates under `~/.rune/registry/templates/<name>/` as `template.ss` + `meta.json` (name, description, version, author, tags, dependencies, min_rune_version, created/updated). Local-only foundation for the Phase 6 shared-template library; remote publishing and `@import "registry:<name>"` resolution are deferred.

### Extracted Sub-Modules

| Parent Module | Extracted Module | Responsibility |
|--------------|-----------------|---------------|
| `parser.zig` | `parse_typedef.zig` | `~` directive parsing (name, base type, dialect overrides) |
| `parser.zig` | `parse_field.zig` | Field declaration parsing (name, type, modifiers, default, check) |
| `parser.zig` | `parse_fk.zig` | Foreign key parsing (inline + standalone, actions) |
| `parser.zig` | `parse_check.zig` | CHECK constraint classification (range, IN, comparison) |
| `parser.zig` | `parse_index.zig` | Index + composite PK parsing |
| `parser.zig` | `parse_template.zig` | Template header parsing + slot detection |
| `parser.zig` | `parse_table.zig` | Table header parsing + engine token stripping |
| `parser.zig` | `parse_trace.zig` | Parser diagnostic trace output (debug mode) |
| `parser.zig` | `parse_recovery.zig` | Error handling + sync point detection for error recovery |
| `parser.zig` | `loc.zig` | Shared `locFromLine` utility — computes `SourceLocation` from tokenized line + token |
| `diff/engine.zig` | `diff/fields.zig` | Field-level diffing + rename detection + equality helpers |
| `diff/engine.zig` | `diff/indexes.zig` | Index diffing |
| `diff/engine.zig` | `diff/fks.zig` | FK diffing |
| `diff/engine.zig` | `diff/semantic.zig` | Dialect-aware type equivalence — `typeInfoEquiv` (AST-level) + `semanticEquiv` (SQL string-level via reverse lookup) |
| `diff/engine.zig` | `diff/format.zig` | Human-readable diff formatting |
| `diff/migrate.zig` | `diff/migrate_helpers.zig` | Shared `emitSingleTable` helper for forward and rollback paths |
| `pipeline/forward.zig` | `pipeline/import_resolver.zig` | `@import` directive resolution — `ImportContext`, `resolveImports`, `splitLines`, `tokenizeAndParseWithLines` |
| `pipeline/handlers.zig` | `pipeline/forward.zig` | CLI output handlers — `handleCompileRequest`, `handleStats`, `generateFromSchema`, `generateFromSchemaBatch`, `handleGenerate`, `handleDocs`, `handleFormat`, `handleExport` |
| `pipeline/validation.zig` | `pipeline/forward.zig` | Validation handlers — `ValidateConfig`, `handleValidate`, `handleCheck` (extracted from handlers.zig for single-responsibility) |
| `pipeline/diff.zig` | `pipeline/forward.zig` | Diff pipeline orchestration — `DiffConfig`, `handleDiff`, `prepareDiff`, `prepareDiffFromSql`, `emitTraceAndStats`, `compileSqlToAst` (SQL-to-AST reverse compilation for `--from-sql`) |
| `pipeline/migrate.zig` | `pipeline/diff.zig` | Migrate pipeline orchestration — `MigrateConfig`, `handleMigrate`, `handleMigrateStatus`, `filterIncrementalChanges`, `collectMigrateFiles`, `findNextSequenceNumber`, `formatMigrationFileName` |
| `codegen/codegen.zig` | `codegen/columns.zig` | Column definition rendering (emitColumnDef, emitColumnDefEx, emitDefault) + shared `isDominatedByExplicitIndex()` |
| `codegen/codegen.zig` | `codegen/indexes.zig` | Inline and standalone index emission |
| `parser/sql_parser.zig` | `parser/sql_parser_helpers.zig` | Identifier/literal/word parsing, whitespace/comment skipping, trailing comment capture, `parseExpression` |
| `parser/sql_parser.zig` | `parser/sql_parser_alter.zig` | ALTER TABLE statement parsing |
| `parser/sql_parser.zig` | `parser/sql_parser_comment.zig` | COMMENT ON TABLE/COLUMN parsing |
| `parser/sql_parser.zig` | `parser/sql_parser_create.zig` | CREATE DATABASE/TABLE/column parsing |
| `parser/sql_parser.zig` | `parser/sql_parser_fk.zig` | Foreign key parsing (reverse pipeline) |
| `parser/sql_parser.zig` | `parser/sql_parser_index.zig` | Index declaration parsing (reverse pipeline) |
| `parser/sql_parser.zig` | `parser/sql_parser_check.zig` | CHECK constraint parsing (reverse pipeline) |
| `reverse/codegen.zig` | `reverse/column.zig` | Column reverse engineering (type mapping, suffix, inline index detection) |
| `reverse/codegen.zig` | `reverse/fk.zig` | FK reverse classification |
| `reverse/codegen.zig` | `reverse/check.zig` | CHECK constraint reverse engineering |
| `reverse/map.zig` | `types/reverse_map.zig` | Shared REVERSE_MAP data + ReverseMapping struct (canonical location) |

## Forward Pipeline

```
Input (.ss text)
    │
    ▼
[1] Tokenizer (tokenizer.zig, 251 lines)
    Line classification + token splitting
    Output: []Line (line_type + tokens)
    │
    ▼
[2] Parser (parser.zig, 623 lines + 9 parse_*.zig modules)
    Token-level parsing into AST
    BlockState struct encapsulates block-level parsing state (12 fields)
    Output: Ast (schema, templates, tables, sql_comments)
    │
    ▼
[3] Template Resolution (template.zig, 212 lines)
    Template inheritance merging + slot-based field injection
    Output: []ResolvedTable (templates applied to each table)
    │
    ▼
[4] Semantic Analyzer (analyzer.zig + pass_manager.zig + 18 pass implementations)
    Pass manager: validate_template_types, resolve_names, resolve_conditionals, resolve_composites,
    autofk,
    suffix_inference, validate, validate_type_modifiers, validate_indexes, validate_duplicates,
    validate_circular_fk, validate_fk_targets, validate_unused_templates, validate_fk_types,
    validate_index_names, validate_views, template_type_conflict
    Output: ResolvedAst (templates resolved + passes applied)
    │
    ▼
[5] Type Resolver (type_resolver.zig, 224 lines + typed_ast.zig, 101 lines)
    Abstract TypeInfo → concrete SqlType per dialect
    Modifier classification into ColumnFlags bitflags
    Output: TypedAst (dialect-agnostic IR)
    │
    ▼
[6] Code Generator (codegen.zig + codegen_columns.zig + codegen_indexes.zig)
    TypedAst → SQL DDL text
    Dialect-specific rendering via DialectBackend vtable
    Output: SQL string
```

### BufferPool (Zero-Allocation Codegen)

`BufferPool` (codegen/codegen.zig) provides reusable `Writer.Allocating` buffers to minimize allocation overhead in batch and parallel codegen:

- **Streaming codegen** (streaming.zig): `StreamingCodegen.initWithPool()` acquires/releases buffers per table
- **Parallel codegen** (parallel.zig): Shared pool across threads with mutex-protected acquire/release
- **Default codegen** (codegen.zig): `generateFromTypedAstPooled()` uses pool for single-schema generation

Thread safety: `BufferPool.acquire()` and `release()` are mutex-protected for safe concurrent access from parallel compilation threads.

### Error Recovery

The pipeline supports graceful degradation:

- **Partial AST**: Parser records all syntax errors and returns partial AST with `error_count`
- **Partial compilation**: Tables with errors are skipped; valid tables still produce SQL output
- **Structured errors**: `DiagnosticCollector` accumulates errors for batch reporting
- **OOM handling**: User-friendly messages with suggestions for reducing memory usage
- **I/O errors**: Clear messages for file not found, access denied, disk full

### IR Boundaries

| IR | Location | Content |
|----|----------|---------|
| `Line[]` | Tokenizer output | Line type + token array |
| `Ast` | Parser output | Schema, templates, tables, SQL comments |
| `[]ResolvedTable` | Template output | Tables with template fields merged |
| `ResolvedAst` | Semantic output | Templates applied + passes run (autofk, suffix_inference, validate) |
| `TypedAst` | TypeResolver output | SQL type strings resolved, modifiers as booleans, `sym_type` for roundtrip |
| `SchemaDiff` | Diff output | Table/field/index/FK diffs with rename detection |

## Reverse Pipeline

```
Input (SQL DDL text)
    │
    ▼
[1] SQL Parser (sql_parser.zig, 545 lines + 8 sql_parser_*.zig modules)
    Recursive-descent DDL parsing (independent of forward tokenizer)
    Output: SqlSchema (tables, columns, indexes, FKs, checks)
    │
    ▼
[2] Reverse Codegen (reverse_codegen.zig, 261 lines, 4 sub-functions)
    SQL types → SS symbols (via reverse_map.zig reverse lookup)
    Template extraction (greedy + scoring algorithm)
    Index inline detection: recognizes both MySQL-style "idx_field" and
    PG/SQLite-style "idx_table_field" as inline index suffixes (@, @u).
    Non-standard index names preserved in full form: @ idx_name (field).
    Confidence comments suppressed on fields with inline index suffixes.
    Output: .ss text (or JSON with --format json)
```

## Diff/Migrate Pipeline

The diff/migrate pipeline has two layers:
1. **Pipeline orchestration** (`pipeline/diff.zig`, `pipeline/migrate.zig`) — CLI handlers that compile schemas, invoke the diff engine, and format output
2. **Diff engine** (`diff/engine.zig` + sub-modules) — Structural comparison with rename detection
3. **Migration generator** (`diff/migrate.zig`) — SchemaDiff → ALTER TABLE SQL

```
(old.ss, new.ss)
    │
    ▼
[1] Pipeline Orchestration (pipeline/diff.zig or pipeline/migrate.zig)
    Compiles both schemas to ResolvedAst via forward pipeline
    │
    ▼
[2] Diff Engine (diff/engine.zig + diff_fields/diff_indexes/diff_fks/diff_format)
    Structural comparison with rename detection
    Output: SchemaDiff
    │
    ├──▶ Diff Printer (human-readable diff output)
    │
    └──▶ Migration Generator (diff/migrate.zig, 6 sub-functions)
         SchemaDiff → ALTER TABLE SQL
         Sub-functions: emitDroppedTables, emitViewDiffs, emitTableDiffs,
         emitFieldDiffs, emitIndexDiffs, emitMetadataDiffs, emitFkDiffs
         FK rendering via DialectBackend.emitForeignKey
         Output: migration SQL
```

## DialectBackend Vtable

32 function pointers (25 required + 7 optional) + 3 behavioral flags + 1 data field (`quoteChar`) for dialect-specific SQL generation (36 fields total). `getBackend()` returns `*const DialectBackend` (pointer to static const, avoids 136-by

> **Generator / dialect coverage matrix** (single source of truth): see [`docs/coverage-matrix.md`](../../docs/coverage-matrix.md).te copy on every call).

```zig
DialectBackend = struct {
    // Core rendering
    quoteIdent:             fn(w, name) -> !void,
    emitIndex:              fn(w, idx, needs_comma) -> !void,
    emitCreateDatabase:     fn(w, name, charset) -> !void,
    emitUnsigned:           fn(w) -> !void,
    emitTimestampModifier:  fn(w, with_on_update) -> !void,
    // Table structure
    emitTableFooter:        fn(w, engine, charset, comment) -> !void,
    emitTableComment:       fn(w, table_name, comment) -> !void,
    emitColumnComment:      fn(w, table_name, col_name, comment) -> !void,
    emitAutoIncrement:      fn(w) -> !void,
    emitPrimaryKey:         fn(w, auto_increment) -> !void,
    emitInlineIndex:        fn(w, col_name, is_unique, needs_comma) -> !void,
    emitStandaloneIndex:    fn(w, table_name, idx) -> !void,
    emitInlineColumnComment: fn(w, comment) -> !void,
    emitEnumTypeCheck:      fn(w, col_name, enum_values) -> !void,
    emitInlineColumnStandaloneIndex: fn(w, table_name, col_name) -> !void,
    // Metadata comments
    emitTypeMetadata:    fn(w, col_name, sym_type) -> !void,
    emitConfidenceComment:  fn(w, confidence) -> !void,
    // ALTER TABLE migration
    emitAlterDropColumn:    fn(w, col_name) -> !void,
    emitAlterModifyColumn:  fn(w, col_name) -> !void,
    emitAlterRenameColumn:  fn(w, old_name, new_name) -> !void,
    emitAlterAddIndex:      fn(w, table_name, idx) -> !void,
    emitAlterDropIndex:     fn(w, idx) -> !void,
    emitAlterDropFk:        fn(w, fk) -> !void,
    commentResult:          fn() -> CommentResult,
    emitAlterTableComment:  fn(w, table_name, comment) -> !void,
    emitAlterEngine:        fn(w, engine) -> !void,
    // View support
    emitCreateView:         fn(w, name, query) -> !void,
    // Type rendering (single source of truth)
    renderType:             fn(w, sql_type) -> !void,
    // FK rendering (shared via dialect/common.zig:emitForeignKeyShared)
    emitForeignKey:         fn(w, fk) -> !void,
    // Reverse engineering (optional)
    reverseLookup:          fn(sql_type, col_name, is_auto_inc, is_default_ts) -> ?ReverseResult,
    // Generated columns (optional)
    emitGeneratedColumn:    fn(w, table_name, col_name, expr, always) -> !void,
    // Type mapping
    lookupSym:              fn(sym) -> ?SqlType,
    quoteChar:              u8,
    // Behavioral flags (eliminate dialect checks in caller)
    rename_needs_column_def: bool,     // MySQL CHANGE COLUMN
    modify_needs_column_def: bool,     // MySQL/PG MODIFY COLUMN
    modify_column_def_skips_name: bool, // PG ALTER COLUMN TYPE
};
```

| Method | MySQL | PostgreSQL | SQLite | MSSQL | Oracle | Db2 |
|--------|-------|-----------|--------|-------|--------|-----|
| `quoteIdent` | backticks | double-quotes | double-quotes | square brackets | double-quotes | double-quotes |
| `emitIndex` | inline INDEX/UNIQUE/FULLTEXT | UNIQUE (...) inline | UNIQUE (...) inline | INDEX/UNIQUE inline | INDEX/UNIQUE inline | INDEX/UNIQUE inline |
| `emitCreateDatabase` | CHARACTER SET | ENCODING | no-op | no-op | no-op | no-op |
| `emitUnsigned` | `UNSIGNED` | no-op | no-op | no-op | no-op | no-op |
| `emitTimestampModifier` | `DEFAULT CURRENT_TIMESTAMP [ON UPDATE ...]` | `DEFAULT CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `emitTableFooter` | `ENGINE=... CHARSET=... COMMENT='...'` | `);` | `);` | `);` | `);` | `);` |
| `emitTableComment` | no-op (in footer) | `COMMENT ON TABLE` | `-- comment` | no-op (sp_addextendedproperty) | `COMMENT ON TABLE` | `COMMENT ON TABLE` |
| `emitColumnComment` | no-op (inline) | `COMMENT ON COLUMN` | `-- table.col: comment` | no-op (sp_addextendedproperty) | `COMMENT ON COLUMN` | `COMMENT ON COLUMN` |
| `emitAutoIncrement` | `AUTO_INCREMENT` | `GENERATED ALWAYS AS IDENTITY` | no-op | no-op | no-op | `GENERATED ALWAYS AS IDENTITY` |
| `emitPrimaryKey` | `PRIMARY KEY` | `PRIMARY KEY` | `PRIMARY KEY [AUTOINCREMENT]` | `PRIMARY KEY` | `PRIMARY KEY` | `PRIMARY KEY` |
| `emitInlineIndex` | `INDEX`/`UNIQUE INDEX` | `UNIQUE (...)` | `UNIQUE (...)` | `INDEX`/`UNIQUE INDEX` | `INDEX`/`UNIQUE INDEX` | `INDEX`/`UNIQUE INDEX` |
| `emitStandaloneIndex` | no-op (inline) | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` |
| `emitInlineColumnComment` | `COMMENT '...'` | no-op (standalone) | no-op (standalone) | `/* comment */` | `/* comment */` | `/* comment */` |
| `emitEnumTypeCheck` | no-op (native ENUM) | `CHECK (... IN (...))` | `CHECK (... IN (...))` | `CHECK (... IN (...))` | `CHECK (... IN (...))` | `CHECK (... IN (...))` |
| `emitInlineColumnStandaloneIndex` | no-op (inline) | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` | `CREATE INDEX` |
| `renderType` | `int`, `bigint`, `smallint`, `decimal`, `varchar`, `text`, `blob`, `json`, `datetime`, `date`, `timestamptz`, `boolean`, `uuid`, `serial` | `integer`, `bigint`, `smallint`, `numeric`, `varchar`, `text`, `bytea`, `json`, `timestamp`, `date`, `timestamptz`, `boolean`, `uuid`, `serial` | `INTEGER`, `NUMERIC`, `varchar`, `TEXT`, `BLOB`, `INTEGER` | `INT`, `BIGINT`, `SMALLINT`, `NUMERIC`, `NVARCHAR`, `NVARCHAR(MAX)`, `VARBINARY(MAX)`, `DATETIME2`, `BIT`, `UNIQUEIDENTIFIER` | `NUMBER(10)`, `NUMBER(19)`, `NUMBER(5)`, `NUMBER(p,s)`, `VARCHAR2`, `CLOB`, `BLOB`, `TIMESTAMP`, `DATE`, `TIMESTAMP WITH TIME ZONE`, `NUMBER(1)`, `RAW(16)` | `INTEGER`, `BIGINT`, `SMALLINT`, `DECIMAL(p,s)`, `VARCHAR`, `CLOB`, `BLOB`, `TIMESTAMP`, `DATE`, `TIMESTAMP WITH TIME ZONE`, `BOOLEAN`, `CHAR(16) FOR BIT DATA` |
| `emitForeignKey` | `FOREIGN KEY (...) REFERENCES ...` | `FOREIGN KEY (...) REFERENCES ...` | `FOREIGN KEY (...) REFERENCES ...` | `FOREIGN KEY (...) REFERENCES ...` | `FOREIGN KEY (...) REFERENCES ...` | `FOREIGN KEY (...) REFERENCES ...` |

PG and SQLite share 7 method implementations (via `common.zig`: `emitIndex`, `emitInlineIndex`, `emitStandaloneIndex`, `emitInlineColumnStandaloneIndex`, `emitAlterDropColumn`, `emitAlterDropIndex`, `emitAlterRenameColumn`). `emitCheckExpr` is a shared standalone function (all dialects use identical CHECK syntax). `emitForeignKey` is shared via `dialect/common.zig:emitForeignKeyShared` (takes `quoteIdent` function pointer).

## Semantic Pass Manager

```zig
SemanticPass = struct { name: []const u8, run: fn(*PassContext) !void, depends_on: []const []const u8, access: PassAccess };
DEFAULT_PASSES = [_]SemanticPass{
    validate_template_types, resolve_names, resolve_conditionals, resolve_composites,
    autofk, suffix_inference,
    validate, validate_type_modifiers, validate_indexes,
    validate_duplicates, validate_circular_fk, validate_fk_targets, validate_unused_templates,
    validate_fk_types, validate_index_names, validate_views, template_type_conflict,
};
```

New passes can be added by:
1. Writing a function with signature `fn(*PassContext) !void`
2. Adding a `SemanticPass` entry to `DEFAULT_PASSES` with `depends_on` and `access` declarations

### Validation Passes (split from `validate_schema` in v0.107.0)

The original monolithic `validate_schema` pass was split into 4 focused passes for single-responsibility:

- **validate_duplicates**: Detects duplicate table names across the schema.
- **validate_circular_fk**: DFS traversal of the FK dependency graph. Detects A→B→C→A cycles and reports them as warnings (non-blocking). Also validates self-referencing FK field counts.
- **validate_fk_targets**: Validates that all FK referenced fields exist in the target table. Reports errors (blocking).
- **validate_unused_templates**: Warns about template definitions that are not referenced by any table or other template.

## Template Extraction Algorithm (Reverse Pipeline)

When `rune reverse -t` is used, the reverse codegen extracts common field sequences across tables and promotes them as reusable templates.

### Algorithm

1. **Candidate generation**: For each table, slide a window of length L (starting from `max_cols`, decrementing to 2) across the column list. Each window position produces a candidate template.

2. **Filtering**: A candidate must contain at least 2 fields not yet covered by previously extracted templates. This prevents degenerate single-field templates.

3. **Matching**: For each candidate, find all tables that contain the same contiguous field sequence (same names + same SQL types, in order). At least 2 tables must match.

4. **Scoring**: `score = matching_tables × field_count × log₂(field_count)`. This favors templates that cover many fields across many tables. Logarithmic weighting on field count prevents excessively large templates from dominating.

5. **Greedy selection**: At each length L, the highest-scoring candidate across all tables is selected. The algorithm then marks those fields as "covered" and repeats.

6. **Early termination**: When `L < 3` and a best candidate already exists, the inner loop breaks (templates smaller than 2 fields are not useful).

7. **Assignment**: After extraction, each table is assigned to its best-matching template (most fields covered). Templates with fewer than 2 assigned tables are discarded.

8. **Naming**: Templates are named `base`, `base2`, `base3`, etc.

### Complexity

- **Time**: O(tables × columns² × L) where L is the sliding window size (bounded by max columns per table).
- **Space**: O(tables × columns) for the candidate and assignment structures.

### Properties

- **Deterministic**: Same input always produces the same output (no randomness).
- **Greedy-optimal**: At each step, picks the locally best template. Does not guarantee global optimum but produces good results in practice.
- **Idempotent**: Re-running on already-templated output produces no additional templates (covered fields are filtered out).

## Type Mapping System

Rune uses a three-layer type mapping system:

- **`sql_type.zig` (SqlType.toSql)**: Delegates to `DialectBackend.renderType` for dialect-aware rendering. Variants: int, bigint, smallint, decimal, varchar, text, blob, json, jsonb, datetime, date, timestamptz, boolean, uuid, inet, serial, enum_values, raw_sql, passthrough. SS symbols: n, N, i, m, M, s, S, b, B, j, J, I, d, t, T, U, p.

- **`type_registry.zig` (CORE_TYPES)**: Static array of 17 SS symbol entries with dialect-specific SQL names. Provides two lookup functions:
  - `lookupSqlType(sym, dialect)` → `?[]const u8` (SQL name string, for backward compat)
  - `lookupSqlTypeDirect(sym, dialect)` → `?SqlType` (direct variant, avoids stringly-typed round-trip)

- **`reverse_map.zig` (REVERSE_MAP)**: 112 entries covering all SQL type variants → SS symbols across 6 dialects (MySQL, PG, SQLite, MSSQL, Oracle, Db2). Used by `reverseLookup()` and `reverseLookupSqlite()`. Includes core entries (for SQLite lossy affinity) plus MySQL/PG variant types, Oracle-specific types (`VARCHAR2(N)`, `NUMBER(P,S)`), Db2-specific types (`DECIMAL(P,S)`), and PostgreSQL-specific passthrough types (xml, cidr, macaddr). Case-insensitive parameterized type matching via `matchPrefix` helper.

## Key Design Decisions

1. **TypedAst IR layer**: Separates type resolution from code generation. Codegen only outputs strings — no type inference logic.
2. **TypeResolver namespace**: Stateless functions (`TypeResolver.resolve`, `TypeResolver.resolveColumn`) that take `Allocator` directly. No struct instantiation — eliminates `init` boilerplate and per-loop allocation overhead in migrate.zig.
3. **DialectBackend vtable**: 32 function pointers (25 required + 7 optional) + 3 behavioral flags + 1 data field (`quoteChar`) cover all dialect differences. Adding a new dialect requires ~300 lines. codegen.zig is fully dialect-agnostic (zero `switch(dialect)` in production code). FK rendering is shared via `dialect/common.zig:emitForeignKeyShared`.
4. **CompileConfig struct**: Replaces 13 positional parameters in `handleCompileRequest`. All fields have named defaults; callers specify only what they need. Improves readability and reduces parameter-ordering bugs.
5. **Self-contained SqlType**: `SqlType.toSql()` delegates to `DialectBackend.renderType`. Adding a new type = add variant to union + add case to all `renderType` implementations + add to `type_registry.zig`. SS symbol naming: lowercase for core types (n, s, b, j, d, t), uppercase for variants (N, M, S, B, T, U, i, p). Unsigned uses `+` prefix (`+n`, `+N`, `+i`).
6. **Direct type lookup**: `type_registry.lookupSqlTypeDirect()` returns `SqlType` variants directly, avoiding the stringly-typed round-trip (SS symbol → SQL string → SqlType).
7. **AST-level diff**: Semantic comparison, not text diff. Detects renames by signature matching. Dialect-aware type equivalence (`diff/semantic.zig`) provides two levels: `typeInfoEquiv` for AST-level TypeInfo comparison and `semanticEquiv` for SQL string-level comparison via reverse lookup. Canonical SS symbol mapping ensures different symbols resolving to the same SQL type are equivalent (e.g., `N4` ↔ `4` in MySQL), but distinct types like `n` (int) vs `N` (bigint) are NOT equivalent.
8. **Arena allocation**: All modules take `std.mem.Allocator`. Arena-style usage for command-lifetime memory.
9. **God function decomposition**: Large functions (>100 lines) are split into focused sub-functions. `migrate.zig:generateFromDiff` (258→7 sub-fns), `codegen.zig:generateTypedTable` (135→5 sub-fns), `reverse_codegen.zig:generateInner` (215→4 sub-fns).
10. **Pipeline-CLI separation**: `pipeline/forward.zig` has no dependency on `cli.zig`. CLI output handlers live in `pipeline/handlers.zig`, keeping the compilation pipeline pure.
11. **Template/Semantic separation**: Template resolution (inheritance, slot merging) is independent of semantic passes (autofk, suffix_inference, validation). Each can be modified without affecting the other.
12. **Custom type system**: Users can define named type aliases via `~` directives in the schema block. Custom types support dialect-specific overrides and are resolved during type resolution (not parsing).
13. **SQLite roundtrip preservation**: `-- @sym col_name type` metadata comments preserve original SS types through lossy SQLite type affinity. Forward compiler emits comments; reverse compiler parses them for exact type restoration.
14. **Unified ReverseResult**: `dialect.zig` defines the single `ReverseResult` struct (`sym`, `omit`, `score`). Both `reverse/map.zig` and `reverse/column.zig` re-export it — zero type duplication across the reverse pipeline.
15. **Generator Registry**: `generator.zig` defines a `Generator` struct (name, description, extension, category, dialects, version, author, generate fn ptr) and a `REGISTRY` array. Generator implementations live in `generators/<name>.zig`. Adding a new generator = create `generators/<name>.zig` + add entry to `REGISTRY`. The CLI dispatches via `generator.get(name)` — no main.zig modification needed. `generator.check()` validates all generators against all 6 dialects (MySQL, PostgreSQL, SQLite, MSSQL, Oracle, Db2) for health validation. Shared helper `generators/common.zig` provides `DefaultFormatter` + `OrmTarget` enum + `getOrmFormatter()` factory for ORM generators (drizzle, knex, typeorm, sqlalchemy) to eliminate duplicated default-value formatting, plus `parseRange`, `parseComparison`, `parseInList`, `writeJsonValue`, and `findFkRefTable` shared by json-schema and openapi generators. Shared test helpers `generators/common_test.zig` provides `makeTestTable`, `makeTestTableWithFks`, `makeTestTableWithIndexes`, `makeTestAst`, `makeTestAstWithName`, `makeTestColumn`, `makeTestColumnWithFlags` for all generator test files. Current generators: `json-schema`, `sql-ddl`, `prisma`, `docs`, `drizzle`, `typeorm`, `sqlalchemy`, `knex`, `openapi`, `graphql`, `symbol-index`, `pydantic`.

16. **Generator Plugin Extensibility**: The planned WASM plugin system extends the existing `Generator` registry by allowing external generators to be discovered and loaded from `.rune-generators/` manifests or WASM modules. Each plugin generator implements the same `generate(alloc, TypedAst, Dialect)` interface. Template overrides can be provided via `.rune-template` files to customize generator output without changing built-in code. The current registry design is intentionally stable so that plugin-based generators remain interoperable with batch generation, CLI metadata, and health checks.
16. **View UNION support**: Views support set operations (UNION, UNION ALL, INTERSECT, EXCEPT). The tokenizer keeps the entire query as a single token. The parser (`parse_table.zig`) detects set operation keywords at the top level (outside quotes) and splits into `query` + `union_op` + `second_query`. The codegen recombines the parts. The diff engine compares views using `viewQueriesEql()` which checks query, union_op, and second_query.

## Custom Type System

Users can define custom type aliases in the schema block:

```
$ mydb
  ~ uuid s36
  ~ email s128
  ~ ip_addr mysql=s45 postgres=inet sqlite=s45

# user
uuid uuid
email email
ip ip_addr
```

### How it works

1. **Tokenizer**: Lines starting with `~` are classified as `TypeDef` (not `Index`)
2. **Parser**: `parseTypeDef()` extracts name, base type, and dialect overrides
3. **Schema**: Custom types are stored in `Schema.custom_types` and passed through `ResolvedAst`
4. **Type resolver**: When resolving a field type, checks custom types first (multi-char names only)
5. **Dialect overrides**: Use `raw_sql` TypeInfo variant to prevent infinite recursion

### Adding a new custom type

No code changes needed — users define types in `.ss` files. For built-in support of a new type:

1. Add variant to `SqlType` union in `sql_type.zig`
2. Add case to `SqlType.toSql()` for dialect rendering
3. Add entry to `CORE_TYPES` in `type_registry.zig` (for single-char symbols)
4. Add to `REVERSE_MAP` in `types/reverse_map.zig` for reverse engineering support
5. Add unit tests and golden file tests

## Composite Type System

Reusable field groupings, declared at top level and embedded inside table bodies (v0.320.0):

```
* audit              ; declaration
created_at t+
updated_at t++

# orders             ; table
id n++
*audit               ; embed — expands in place here
total m
```

### How it works

1. **Tokenizer**: Lines starting with `*` are classified as `Composite`
2. **Parser**: Top-level `*name` opens a composite block (fields collected until the next block header); `*name` inside a table body records a `CompositeEmbed` (name + insert position) in `Table.embeds`
3. **AST**: Declarations live in `Ast.composites`; embed sites live in `Table.embeds` (carried through template resolution into `ResolvedTable.embeds`)
4. **Semantic pass**: `resolve_composites` (between `resolve_conditionals` and `autofk`) splices each embed's fields at its recorded position; errors on unknown references, duplicate definitions, empty composites; warns on unused composites
5. **Downstream**: expansion happens before autofk/suffix_inference/validate/diff — all later stages see plain fields

Composites vs templates: templates merge at the whole-table level with `...` slot control and support inheritance/mixins; composites embed a field group at any position, multiple times per table.

## Adding a New SQL Dialect

1. Add variant to `Dialect` enum in `dialect/enum.zig`
2. Create `DialectBackend` instance in `dialect/<name>.zig` (~300 lines, self-contained type mapping)
3. Register in `getBackend()` switch in `dialect.zig`
4. Add comptime validation call in `dialect.zig` (`comptimeValidateAllPointers`)
5. Update CLI `parseDialect` to accept dialect aliases
6. Add reverse mappings to `REVERSE_MAP` in `types/reverse_map.zig`
7. Update `DialectTypeMap` struct with new dialect field
8. Add golden file tests in `tests/`
9. Update documentation (README.md, schemaspec/type.md, schemaspec/schema.md, ARCHITECTURE.md)

No changes needed in `codegen.zig` — it is fully dialect-agnostic.

## Benchmark Infrastructure

`src/bench.zig` measures per-stage latency for the forward pipeline using `Io.Clock.Timestamp` (nanosecond precision). Supports per-dialect benchmarking via `--dialect` flag. Refactored into `BenchArgs` config struct, `parseBenchArgs` helper, `stagePairs` shared iteration, and `Baseline.total()` method.

### Schema Sizes

| File | Tables | Fields | Description |
|------|--------|--------|-------------|
| `bench/small.ss` | 6 | ~30 | Blog-like schema (user, post, comment, tag) |
| `bench/medium.ss` | 21 | ~200 | Project management (users, projects, issues, PRs) |
| `bench/large.ss` | 32 | ~400 | Enterprise platform (tenants, tasks, sprints, audits) |

## SS Formatter

`src/formatter.zig` auto-formats `.ss` files with consistent style: strip trailing whitespace, 2-space indentation for fields, single blank lines between blocks, SQL keyword uppercasing inside `@if`/`@endif` conditional blocks. The formatter supports dialect-aware formatting via `formatDialect(alloc, input, dialect)` — when a dialect is specified (e.g., `.mysql`, `.pg`), dialect-specific SQL keywords are also uppercased (e.g., `AUTO_INCREMENT` for MySQL, `SERIAL` for PostgreSQL). The `--write` flag writes formatted output back to the input file in-place. The LSP server uses the configured dialect for document formatting.

### Usage

```bash
zig build bench                              # default: small, mysql, 50 iterations
zig build bench -- --dialect pg              # benchmark PostgreSQL dialect
zig build bench -- --dialect oracle          # benchmark Oracle dialect
zig build bench -- --save --dialect pg       # save PG baseline
zig build bench -- bench/medium.ss 20       # custom file + count
zig build bench -- bench/large.ss 5         # large schema
```

### Pipeline Stages Measured

1. **Tokenize**: Line splitting + token classification
2. **Parse**: Token-level parsing into AST
3. **Semantic**: Template resolution + pass manager (autofk, suffix_inference, validate)
4. **Type Resolve**: TypeInfo → SqlType per dialect
5. **Codegen**: TypedAst → SQL DDL text via DialectBackend vtable

## Testing Strategy

| Layer | Files | Count | Coverage |
|-------|-------|-------|----------|
| Unit tests | 119 colocated `*_test.zig` files (wired via `tests.zig` comptime index) + inline tests in `diff/fields.zig`, `semantic/pass/*.zig` | ~1,936+ | Core logic + pipeline + colocated |
| MySQL golden | `tests/test.sh` | 85 | Full pipeline |
| PG golden | `tests/test_postgres.sh` | 86 | Full pipeline |
| SQLite golden | `tests/test_sqlite.sh` | 26 | Full pipeline |
| MSSQL golden | `tests/test_mssql.sh` | 26 | Full pipeline |
| Oracle golden | `tests/test_oracle.sh` | 103 | Full pipeline |
| Db2 golden | `tests/test_db2.sh` | 103 | Full pipeline |
| Migrate golden | `tests/test_migrate.sh` | 34 | Diff + migration SQL |
| Reverse golden | `tests/test_reverse.sh` | 21 | SQL → .ss |
| Reverse Oracle | `tests/test_reverse_oracle.sh` | 5 | Oracle SQL → .ss |
| Reverse Db2 | `tests/test_reverse_db2.sh` | 5 | Db2 SQL → .ss |
| Diff golden | `tests/test_diff.sh` | 12 | Schema comparison |
| Error recovery | `tests/test_error_recovery.sh` | 12 | Parse error handling + schema-level validation |
| JSON Schema | `tests/test_json_schema.sh` | 3 | JSON Schema output |
| Roundtrip | `tests/test_roundtrip.sh` | 112 | Forward → reverse fidelity |
| Imports | `tests/test_imports.sh` | 6 | Import system |
| Stdin | `tests/test_stdin.sh` | 4 | Stdin pipeline |
| Reverse confidence | `tests/test_reverse_confidence.sh` | 3 | Reverse confidence scores |
| Init & completions | `tests/test_init.sh` | 12 | Init & completions |
| **Total** | | **~1,936+** | |

## Lint Module

The lint module (`rune lint`) analyzes `.ss` schemas for quality issues. It runs after semantic analysis and produces diagnostic results. Supports 85 rules, 11 auto-fixable, with `--show-rules` and `--init` for discoverability.

### Sub-modules

| File | Lines | Responsibility |
|------|-------|---------------|
| `lint/rules.zig` | ~130 | Data-driven dispatch table (`RULES` array), `RuleInfo`/`RULE_INFO`, helper functions (`isSnakeCase`, `isUpperSnakeCase`), `runAll()` orchestrator |
| `lint/handlers/structural.zig` | ~120 | Structural rules: no-pk, no-timestamps, wide-table, count, empty-table, table-comment, table-name-length |
| `lint/handlers/naming.zig` | ~120 | Naming rules: naming, naming-prefix, fk-naming, index-naming, timestamp-naming, enum-value-naming, column-boolean-naming, column-unique-naming |
| `lint/handlers/validation.zig` | ~300 | Validation rules: nullable-pk, enum-case, orphan-type, index-unused, circular-fk, bool-default, view-no-select, column-default-required, nullable-column-default, fk-null, duplicate-column, unique-constraint, composite-pk |
| `lint/handlers/compat.zig` | ~80 | Compatibility rules: serial-type, column-length, cross-dialect-types, reserved-word, column-type-portability |
| `lint/handlers/fk.zig` | ~120 | FK rules: fk-cascade, fk-self-reference, fk-depth, fk-duplicate, fk-column-type-mismatch, fk-on-delete-cascade |
| `lint/handlers/index.zig` | ~95 | Index rules: duplicate-index, index-column-missing, index-missing-fk-columns, index-columns-max, index-redundant-with-pk, index-consistency-pass, unique-prefix-redundancy, unique-index-redundant-with-fk, unique-index-redundant-with-pk, unique-index-redundant-with-unique |
| `lint/handlers/view.zig` | ~80 | View rules: view-no-alias, view-naming, view-select-star, view-dependency-cycle |
| `lint/handlers/enum.zig` | ~80 | Enum rules: enum-value-naming, enum-empty, enum-value-duplicate |
| `lint/handlers/portability.zig` | ~60 | Portability rules: column-type-portability, reserved-word, column-auto-increment-type, column-auto-increment-nullable, table-no-index |
| `lint/config.zig` | ~300 | `LintConfig` struct with toggle flags, `LintRule` enum (single source of truth for rule names + descriptions + enable/disable + exhaustive isFixable/lintLevel switches), `LintRules` TOML config parsing, severity/threshold configuration |
| `lint/format.zig` | ~160 | Output formatters: text (human-readable with summary line), JSON (machine-readable), SARIF (CI/CD integration) |
| `lint/fix.zig` | ~250 | Auto-fix logic for fixable rules (no-pk, no-timestamps, empty-table, serial-type, bool-default, nullable-column-default, duplicate-index, column-default-required, no-index-fk, duplicate-column, index-missing-fk-columns) |
| `lint.zig` | ~33 | Re-export barrel module |

### Lint Rules

| Rule | Description | Fixable |
|------|-------------|---------|
| `no-pk` | Table has no primary key | Yes |
| `naming` | Table/column name not snake_case | No |
| `no-index-fk` | Foreign key column without index | Yes |
| `no-timestamps` | Table missing created_at/updated_at | Yes |
| `wide-table` | Table exceeds column threshold (default 30) | No |
| `enum-case` | Custom type name not UPPER_CASE | No |
| `count` | Table has too few columns | No |
| `fk-cascade` | FK missing ON DELETE/ON UPDATE actions | No |
| `nullable-pk` | Primary key column is nullable | No |
| `orphan-type` | Custom type defined but not used | No |
| `index-unused` | Non-FK, non-unique index may be unused | No |
| `circular-fk` | Circular FK dependency detected | No |
| `duplicate-index` | Duplicate index on same columns | Yes |
| `empty-table` | Table has zero columns | Yes |
| `table-comment` | Table has no comment | No |
| `serial-type` | PostgreSQL-specific serial type used | Yes |
| `table-name-length` | Table name exceeds max length (default 64) | No |
| `column-length` | String column has no explicit length | No |
| `index-column-missing` | Index references column not in table | No |
| `naming-prefix` | Table name uses anti-pattern prefix (tbl_, t_, tb_) | No |
| `fk-naming` | FK column doesn't follow `<table>_id` convention | No |
| `bool-default` | Boolean column without explicit default | Yes |
| `view-no-select` | View has no SELECT statement | No |
| `column-default-required` | Non-PK non-nullable column without DEFAULT | Yes |
| `index-naming` | Index name doesn't follow `<table>_<columns>` convention | No |
| `nullable-column-default` | Nullable non-PK column without DEFAULT | Yes |
| `timestamp-naming` | Datetime column should be created_at/updated_at | No |
| `enum-value-naming` | Enum values should be UPPER_CASE | No |
| `fk-null` | Foreign key column is nullable | No |
| `cross-dialect-types` | MySQL-specific types not portable to other dialects | No |
| `view-no-alias` | View SELECT uses expressions without column aliases | No |
| `fk-self-reference` | Foreign key references the same table (self-reference) | No |
| `enum-empty` | Custom type enum has no values | No |
| `view-naming` | View name doesn't follow `<entity>_view` or `v_<entity>` convention | No |
| `duplicate-column` | Table has columns with the same name | Yes |
| `view-select-star` | View uses SELECT * (prefer explicit columns) | No |
| `enum-value-duplicate` | Custom type has duplicate enum values | No |
| `column-boolean-naming` | Boolean column should use is_/has_/can_ prefix | No |
| `fk-depth` | FK reference chain exceeds 3 levels | No |
| `unique-constraint` | UNIQUE constraint on column that is already the primary key | No |
| `composite-pk` | Multiple auto-increment primary keys in one table | No |
| `fk-duplicate` | Multiple foreign keys reference the same target table | No |
| `reserved-word` | Table or column name uses a SQL reserved word | No |
| `column-type-portability` | Column type may not be portable across dialects | No |
| `index-missing-fk-columns` | Table has FKs but no index on FK columns | Yes |
| `index-columns-max` | Index has too many columns (configurable threshold) | No |
| `column-name-too-long` | Column name exceeds max length (configurable, default 64) | No |
| `index-redundant-with-pk` | Index duplicates the primary key columns | No |
| `unique-prefix-redundancy` | Standalone unique index is a redundant leading-column prefix of a larger UNIQUE or PRIMARY-KEY index | No |
| `unique-index-redundant-with-fk` | Standalone unique index duplicates the index auto-created for a foreign key column (completes the FK-redundancy direction for both regular and unique indexes) | No |
| `unique-index-redundant-with-pk` | Standalone unique index duplicates the index auto-created for the primary key (completes the PK-redundancy direction for both regular and unique indexes; disjoint from `index-redundant-with-pk` by index kind) | No |
| `view-dependency-cycle` | Views reference each other in a cycle | No |
| `column-unique-nullable` | UNIQUE constraint on nullable column (multiple NULLs allowed) | No |
| `fk-column-type-mismatch` | FK column type doesn't match referenced column type | No |
| `column-auto-increment-type` | Auto-increment used on non-integer type | No |
| `column-unique-naming` | Columns differ only by case (potential naming conflict) | No |
| `fk-on-delete-cascade` | Foreign key uses ON DELETE CASCADE (potential data loss) | No |
| `column-auto-increment-nullable` | Auto-increment on nullable column (should be NOT NULL) | No |
| `table-no-index` | Table has no indexes (potential performance issue) | No |

### Diff-Aware Lint

`lintDiff(old, new)` compares two lint result sets and returns `added`/`removed`/`unchanged` arrays. Used by `rune lint --diff` to show only new issues introduced by schema changes.

## LSP Server

The LSP server (`rune lsp`) provides IDE integration via JSON-RPC over stdio. It runs the compilation pipeline on document open/change and caches the `TypedAst` for interactive features. Request handlers are extracted to `handlers.zig` for maintainability.

### Sub-modules

| Module | Lines | Responsibility |
|--------|-------|---------------|
| `lsp/server.zig` | ~629 | JSON-RPC main loop, request dispatch (22 methods) |
| `lsp/protocol.zig` | ~869 | LSP protocol types and JSON serialization |
| `lsp/documents.zig` | ~188 | Document state manager (open/change/close) |
| `lsp/handlers.zig` | ~380 | Request handlers (initialize, shutdown, didOpen/didChange/didClose/didSave, completion, hover, definition, codeAction, formatting, rename, references, highlights, workspace symbol, signature help, inlay hints, code lens) |
| `lsp/compile_service.zig` | ~202 | Pipeline wrapper for LSP diagnostics |
| `lsp/features.zig` | ~30 | Thin facade re-exporting sub-modules |
| `lsp/helpers.zig` | ~50 | Shared `makeRange`, `getLineText`, `lineLength`, `formatFlagsForHover` utilities |
| `lsp/document_symbols.zig` | ~200 | Outline view (tables, columns, FKs, indexes) |
| `lsp/completions.zig` | ~250 | Context-sensitive completion (keywords, types, modifiers) |
| `lsp/hover.zig` | ~200 | Hover info (table stats, column types, FK relationships) |
| `lsp/go_to_definition.zig` | ~50 | Navigate FK references to target tables |
| `lsp/code_actions.zig` | ~150 | Quick fixes (add PK, add comment, snake_case, FK index). All actions are built via `appendCodeAction`, which heap-copies changes/diagnostics — anonymous struct literals there held dangling stack pointers (fixed v0.323.0) |
| `lsp/rename.zig` | ~130 | Symbol rename with reference tracking |
| `lsp/references.zig` | ~100 | Find all references to a table or column name |
| `lsp/highlights.zig` | ~100 | Document highlights — highlight all occurrences of symbol under cursor |
| `lsp/formatting.zig` | ~10 | Document formatting via formatter |
| `lsp/inlay_hints.zig` | ~80 | Inlay hints — show resolved SQL types inline in the editor |

### Data flow

```
Editor → JSON-RPC → server.zig dispatch → handlers.zig
  ├── textDocument/didOpen/didChange → compile_service.zig → pipeline → TypedAst cache
  ├── textDocument/completion → completions.zig → CompletionList
  ├── textDocument/hover → hover.zig → Hover (markdown)
  ├── textDocument/definition → go_to_definition.zig → Location
  ├── textDocument/references → references.zig → Location[]
  ├── textDocument/documentHighlight → highlights.zig → DocumentHighlight[]
  ├── textDocument/codeAction → code_actions.zig → CodeAction[]
  ├── textDocument/rename → rename.zig → WorkspaceEdit
  ├── textDocument/formatting → formatting.zig → TextEdit[]
  └── textDocument/inlayHint → inlay_hints.zig → InlayHint[]
```

## Watch Mode

`rune watch` monitors `.ss` files and recompiles on change.

### Implementation

`src/watch.zig` uses polling-based file monitoring with per-file hash tracking. On each poll cycle:
1. Recursively scan the directory for `.ss` files (if `--recursive`)
2. Compute file modification hashes
3. Recompile only files that changed
4. Track error streaks (suppress repeated errors for the same file)

### Options

- `--interval <ms>` — Polling interval (default: 1000ms)
- `--parallel` — Compile multiple changed files concurrently
- `-s` — Show compilation stats on each recompile

## Tune Command

`rune tune` auto-extracts common field sequences into reusable templates.

### Implementation

`src/tune.zig` analyzes a schema file and identifies fields that co-occur across multiple tables. It then:
1. Scores field sequences by frequency × field_count × log₂(field_count)
2. Greedily selects the highest-scoring sequences as templates
3. Rewrites the `.ss` file with `#base table` references

### Options

- `--dry-run` — Preview template extraction without writing

## Platform Support

Rune supports multiple platforms via Zig's cross-compilation:

| Platform | Target Triple | Status | Notes |
|----------|--------------|--------|-------|
| Linux x86_64 | `x86_64-linux` | ✅ Primary | Full test coverage |
| Linux ARM64 | `aarch64-linux` | ✅ CI | Cross-compiled, golden tests via QEMU |
| macOS x86_64 | `x86_64-macos` | ✅ Release | Cross-compiled |
| macOS ARM64 | `aarch64-macos` | ✅ Release | Cross-compiled |
| Windows x86_64 | `x86_64-windows` | ✅ CI | Unit tests + build validation |
| WASM (WASI) | `wasm32-wasi` | ✅ Library | WASM library for browser/Deno usage |

### WASM Architecture

WASM builds use a separate entry point (`src/wasm.zig`) instead of `src/main.zig`. The WASM module is organized into focused sub-modules:

- `wasm.zig` — Entry point, re-exports all sub-modules
- `wasm/common.zig` — Shared state (global arena, error handling) and option parsing helpers
- `wasm/error.zig` — Error state management (`rune_last_error`, `rune_last_error_code`, `rune_reset`, `rune_version`)
- `wasm/compile.zig` — Compilation functions (`rune_compile`, `rune_stats`, `rune_validate`)
- `wasm/diff.zig` — Diff and migration functions (`rune_diff`, `rune_migrate`)
- `wasm/reverse.zig` — Reverse engineering functions (`rune_reverse`)
- `wasm/lint.zig` — Lint functions (`rune_lint`)
- `wasm/format.zig` — Formatting and template extraction (`rune_format`, `rune_tune`)
- `wasm/generate.zig` — Generator functions (`rune_generate`)

The WASM module exports C-compatible functions:

- `rune_compile(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — compile schema to SQL
- `rune_diff(schema1_ptr, schema1_len, schema2_ptr, schema2_len, options_ptr, options_len) → ?[*:0]const u8` — diff two schemas
- `rune_migrate(schema1_ptr, schema1_len, schema2_ptr, schema2_len, options_ptr, options_len) → ?[*:0]const u8` — generate migration SQL
- `rune_reverse(sql_ptr, sql_len, options_ptr, options_len) → ?[*:0]const u8` — reverse-engineer SQL to .ss
- `rune_lint(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — lint schema
- `rune_format(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — format .ss schema text
- `rune_tune(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — auto-extract templates
- `rune_generate(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — generate via pluggable generator
- `rune_stats(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — schema statistics as JSON
- `rune_validate(schema_ptr, schema_len, options_ptr, options_len) → ?[*:0]const u8` — validate schema as JSON
- `rune_version() → ?[*:0]const u8` — get version string
- `rune_last_error() → ?[*:0]const u8` — get last error message
- `rune_last_error_code() → i32` — get numeric error code (0=success, 1=syntax, 2=type, 3=FK, 4=semantic, 5=unknown)
- `rune_reset() → void` — free all allocated memory

Key WASM adaptations:
- `codegen/parallel.zig`: sequential compilation fallback (no threads on WASM)
- `build.zig`: automatically selects `wasm.zig` entry point for wasm32 targets

JavaScript wrapper (`wasm/rune.js`) provides `compile()` and `version()` APIs for Deno and browser environments.

### Build Commands

```bash
zig build -Dtarget=wasm32-wasi              # Build WASM library
zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSafe  # Release WASM
```
