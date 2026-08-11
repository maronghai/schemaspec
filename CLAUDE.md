# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Rune is a minimal DSL for declaring database schemas using single-character symbols, implemented in Zig. It compiles `.ss` schema files into SQL DDL (MySQL/PostgreSQL/SQLite/MSSQL/Oracle/Db2), and supports reverse engineering (SQL→.ss), schema diff, and migration generation.

## Build & Test Commands

```bash
cd rune && zig build                          # Build (debug)
cd rune && zig build -Doptimize=ReleaseSafe   # Build (release)
cd rune && zig build test                     # Unit tests (colocated Zig test files)
cd rune && zig fmt --check src/               # Formatting check
cd rune && zig build bench                    # Benchmark (per-stage pipeline timing)
cd rune && zig build bench -- --save           # Save current timing as baseline
cd rune && zig build bench -- --check          # Check for regressions vs baseline (>10% = exit 1)
cd rune && zig build bench -- --dialect pg     # Benchmark PostgreSQL dialect
cd rune && zig build -Dtarget=wasm32-wasi     # Build WASM library (browser/Deno)
```

### Golden File Tests (shell-based, compare compiler output against .sql golden files)

```bash
bash tests/test.sh                  # MySQL (85 tests)
bash tests/test_postgres.sh         # PostgreSQL (86 tests)
bash tests/test_sqlite.sh           # SQLite (26 tests)
bash tests/test_mssql.sh            # MSSQL (26 tests)
bash tests/test_oracle.sh           # Oracle (103 tests)
bash tests/test_db2.sh              # Db2 (103 tests)
bash tests/test_migrate.sh          # Migration (34 tests)
bash tests/test_migrate_status.sh   # Migrate status (7 tests)
bash tests/test_reverse.sh          # Reverse engineering (21 tests)
bash tests/test_reverse_oracle.sh   # Oracle reverse engineering (5 tests)
bash tests/test_reverse_db2.sh      # Db2 reverse engineering (5 tests)
bash tests/test_diff.sh             # Schema diff (12 tests)
bash tests/test_error_recovery.sh   # Error recovery (12 tests)
bash tests/test_json_schema.sh      # JSON Schema (3 tests)
bash tests/test_roundtrip.sh        # Round-trip (112 tests, 5 dialects)
bash tests/test_property_roundtrip.sh  # Property-based roundtrip (30+ iterations)
bash tests/test_imports.sh          # Import system (6 tests)
bash tests/test_stdin.sh            # Stdin pipeline (4 tests)
bash tests/test_bench.sh            # Benchmark regression (--save/--check/--diff)
bash tests/test_reverse_confidence.sh  # Reverse confidence (3 tests)
bash tests/test_init.sh             # Init & completions (12 tests)
bash tests/test_color.sh            # Color output (5 tests)
bash tests/test_validate.sh         # Validate command (4 tests)
bash tests/test_stats_json.sh       # Stats JSON output (3 tests)
bash tests/test_format.sh           # Formatter golden tests (10 tests)
bash tests/test_coverage.sh         # Full test suite runner (all 25 suites)
```

Run a single golden test by filter: `bash tests/test.sh 01` (matches test name substring).

### Quick Usage

```bash
./rune/zig-out/bin/rune schema.ss                        # Compile to stdout
./rune/zig-out/bin/rune schema.ss -o out.sql             # Compile to file
./rune/zig-out/bin/rune schema.ss -d pg                  # PostgreSQL output
./rune/zig-out/bin/rune schema.ss -d sqlite              # SQLite output
./rune/zig-out/bin/rune schema.ss -d mssql               # MSSQL output
./rune/zig-out/bin/rune schema.ss -d oracle              # Oracle output
./rune/zig-out/bin/rune schema.ss -d db2                 # Db2 output
./rune/zig-out/bin/rune validate schema.ss               # Validate schema (no output)
./rune/zig-out/bin/rune validate schema.ss -s            # Validate with stats
./rune/zig-out/bin/rune validate schema.ss --fix        # Validate and auto-fix issues
./rune/zig-out/bin/rune validate schema.ss --format json # Validate as JSON
./rune/zig-out/bin/rune validate schema.ss --format sarif # Validate as SARIF
./rune/zig-out/bin/rune stats schema.ss                  # Print schema statistics
./rune/zig-out/bin/rune stats schema.ss --format json    # Stats as JSON
./rune/zig-out/bin/rune stats schema.ss --per-table      # Per-table breakdown
./rune/zig-out/bin/rune init                             # Create starter schema
./rune/zig-out/bin/rune init myapp                       # Create starter schema with name
./rune/zig-out/bin/rune init --output-dir src/schema    # Create in subdirectory
./rune/zig-out/bin/rune --init                           # Create starter schema (flag equivalent)
./rune/zig-out/bin/rune completions bash                 # Generate bash completions
./rune/zig-out/bin/rune completions zsh                  # Generate zsh completions
./rune/zig-out/bin/rune migrate old.ss new.ss           # Migration SQL
./rune/zig-out/bin/rune migrate old.ss new.ss --rollback # Rollback SQL
./rune/zig-out/bin/rune migrate --graph migrations/      # Migration dependency graph
./rune/zig-out/bin/rune reverse schema.sql -t             # Reverse-engineer with template extraction
./rune/zig-out/bin/rune reverse schema.sql --format json  # Reverse-engineer to JSON
./rune/zig-out/bin/rune reverse schema.sql --check        # CI gate (exit 1 on errors)
./rune/zig-out/bin/rune docs schema.ss                   # Generate Markdown documentation
./rune/zig-out/bin/rune format schema.ss                    # Auto-format .ss file
./rune/zig-out/bin/rune format schema.ss --check            # Check if formatting needed
./rune/zig-out/bin/rune format schema.ss --write             # Format in-place
./rune/zig-out/bin/rune format schema.ss --write -d pg       # Format in-place with PostgreSQL keywords
./rune/zig-out/bin/rune format schema.ss --diff             # Show formatting differences
./rune/zig-out/bin/rune tune schema.ss                      # Extract common fields into templates
./rune/zig-out/bin/rune tune schema.ss --dry-run            # Preview template extraction
./rune/zig-out/bin/rune diff old.ss new.ss --format sarif # SARIF diff output
./rune/zig-out/bin/rune diff old.ss new.ss --check       # CI gate (exit 1 if differences)
./rune/zig-out/bin/rune diff old.ss new.ss --summary     # Summary only (N changed, X added, Y dropped, Z modified)
./rune/zig-out/bin/rune diff old.ss new.ss --stat        # Summary only (alias for --summary)
./rune/zig-out/bin/rune diff schema.ss --from-sql live.sql # Drift detection against SQL dump
./rune/zig-out/bin/rune diff schema.ss --from-sql live.sql --check # CI drift gate
./rune/zig-out/bin/rune generate json-schema schema.ss   # Generate JSON Schema
./rune/zig-out/bin/rune generate --list                  # List available generators with metadata
./rune/zig-out/bin/rune generate schema.ss --generators prisma,drizzle,openapi  # Batch generation
./rune/zig-out/bin/rune generate schema.ss --dry-run     # Preview generate output without writing
./rune/zig-out/bin/rune export schema.ss                  # Export schema as JSON
./rune/zig-out/bin/rune export schema.ss --format text    # Export as text summary
./rune/zig-out/bin/rune export schema.ss --format markdown # Export as Markdown
./rune/zig-out/bin/rune watch schema.ss                   # Watch file and recompile on change
./rune/zig-out/bin/rune watch schema.ss --interval 500    # Watch with 500ms polling interval
./rune/zig-out/bin/rune watch schema.ss --stream           # Watch with streaming compilation
./rune/zig-out/bin/rune watch schema.ss --parallel         # Watch with parallel compilation
./rune/zig-out/bin/rune watch schema.ss -s                 # Watch with compilation stats
./rune/zig-out/bin/rune watch schemas/ --recursive         # Watch directory recursively
./rune/zig-out/bin/rune lint schema.ss                    # Lint schema for quality issues (49 rules)
./rune/zig-out/bin/rune lint schema.ss --fix              # Lint and auto-fix issues (11 rules: no-pk, no-timestamps, empty-table, serial-type, bool-default, nullable-column-default, duplicate-index, index-column-missing, column-default-required, no-index-fk, duplicate-column)
./rune/zig-out/bin/rune lint schema.ss --fix --dry-run    # Preview fixes without writing
./rune/zig-out/bin/rune lint schema.ss --json-errors      # Lint as JSON
./rune/zig-out/bin/rune lint schema.ss --strict           # Lint, exit 1 on warnings
./rune/zig-out/bin/rune lint --show-rules                 # List all available rules with descriptions
./rune/zig-out/bin/rune lint --init                       # Generate starter .rune-lint.toml config
./rune/zig-out/bin/rune migrate old.ss new.ss             # Migration SQL (auto-lint fixes applied to new schema)
./rune/zig-out/bin/rune migrate old.ss new.ss --no-lint   # Migration SQL without auto-lint
./rune/zig-out/bin/rune lsp                               # Start LSP language server (stdio)
```

### Installation

```bash
# Docker (recommended for CI/CD)
docker pull ghcr.io/rune-lang/rune:latest
docker run --rm -v $(pwd):/workspace ghcr.io/rune-lang/rune:latest schema.ss

# Homebrew (macOS/Linux)
brew install rune

# Scoop (Windows)
scoop install rune-schema

# npm (cross-platform)
npm install -g rune-schema
```

### Migration

See [docs/migration-guide.md](docs/migration-guide.md) for migrating from SQL DDL, Prisma, or Knex.

### VS Code Extension

```bash
cd packaging/vscode && code --install-extension .
```

Provides: syntax highlighting (TextMate grammar), language configuration (brackets, comments, folding), LSP-powered IntelliSense (completion, hover, go-to-definition, diagnostics, code actions, formatting, workspace symbols, signature help, inlay hints, code lens), and commands (`Rune: Validate`, `Rune: Generate SQL`, `Rune: Initialize Schema`). The extension starts `rune lsp` automatically on activation. Configure `rune.schemaPath` for custom binary paths.

## Architecture

### Source Layout

```
rune/src/
  main.zig, cli.zig, io.zig, utils.zig, completions.zig, color.zig, config.zig, config_merge.zig  # CLI + glue
  wasm.zig                                                   # WASM library entry point (wasm32-wasi)
  wasm/common.zig, wasm/error.zig, wasm/compile.zig,        # WASM sub-modules (split from monolith)
  wasm/diff.zig, wasm/reverse.zig, wasm/lint.zig,
  wasm/format.zig, wasm/generate.zig, wasm/export.zig,
  wasm/docs.zig
  cli/init.zig, cli/hooks.zig                             # init + hooks (split from completions.zig)
  bench.zig, ast_visitor.zig, formatter.zig, lint.zig, version.zig  # standalone modules (lint.zig = barrel for lint/ sub-modules)
  lint/rules.zig, lint/format.zig, lint/config.zig, lint/fix.zig  # lint engine split
  lint/handlers/structural.zig, lint/handlers/naming.zig, lint/handlers/validation.zig, lint/handlers/compat.zig  # handler modules
  cli/lint_cmd.zig                                                 # lint CLI handler (extracted from main.zig)
  cli/errors.zig                                                   # CLI error handling (extracted from main.zig)
  generator.zig                                                   # generator registry (pluggable)
  lsp/          protocol.zig, documents.zig,                # LSP server (JSON-RPC, document sync, completion, hover, go-to-def, code actions, formatting, references, highlights, workspace symbols, signature help, code lens)
                compile_service.zig, server.zig, features.zig
  generators/      common.zig, common_test.zig, json_schema.zig, sql_ddl.zig, prisma.zig, docs.zig, drizzle.zig, typeorm.zig, sqlalchemy.zig, knex.zig, openapi.zig, graphql.zig  # generator implementations + shared test helpers
  tests.zig                                                       # colocated test index (109 files)
  utils/      edit_distance.zig                         # edit distance + suggestion
  pipeline/    forward.zig, handlers.zig, validation.zig,  # pipeline orchestration + CLI handlers
               reverse.zig, diff.zig, migrate.zig, export.zig, stats.zig
  parser/      tokenizer.zig, parser.zig, parse_*.zig,   # forward parser (13 files)
               sql_parser*.zig
  codegen/     codegen.zig, columns.zig, indexes.zig,    # SQL code generation
               streaming.zig, parallel.zig, deps.zig    # streaming, parallel compilation, dependency analysis
  dialect/     dialect.zig, enum.zig, mysql.zig,          # dialect backends (8 files)
               pg.zig, sqlite.zig, mssql.zig, oracle.zig,
               common.zig, sqlite_hints.zig
  reverse/     codegen.zig, column.zig, map.zig,          # reverse engineering (9 files)
               map_data.zig, fk.zig, check.zig,
               dialect_detect.zig, template_extraction.zig
  diff/        engine.zig, types.zig, fields.zig,         # diff/migrate (24 files)
               fks.zig, indexes.zig, semantic.zig, migrate.zig, rename.zig
               plan.zig,                                  # Migration Plan IR
               format.zig, format_common.zig,            # format re-export + shared helpers
               format/text.zig, format/json.zig,         # format sub-modules
               format/sarif.zig, format/markdown.zig
               emit.zig, migrate_helpers.zig, migrate_json.zig,
               migrate_graph.zig                         # migration dependency graph
  types/       ast.zig, resolved_ast.zig, typed_ast.zig,  # type system (10 files)
               sql_type.zig, type_registry.zig,
               type_resolver.zig, symbol_table.zig,
               reverse_map.zig                            # shared REVERSE_MAP data
  semantic/    analyzer.zig, pass_manager.zig,            # semantic analysis (6 files)
               trace.zig, diagnostic.zig, template.zig,
               test_helpers.zig, pass/*.zig               # 14 pass implementations
```

### Three Pipelines

1. **Forward**: `.ss` → (Import Resolution) → Tokenizer → Parser → Template Resolution → Semantic Analyzer → Type Resolver → Codegen → SQL
2. **Reverse**: SQL DDL → SqlParser → ReverseCodegen (with optional template extraction) → `.ss`
3. **Diff/Migrate**: Two `.ss` files each compile to `ResolvedAst` → DiffEngine produces `SchemaDiff` → MigrationGenerator outputs ALTER TABLE SQL (or rollback SQL with `--rollback`)

### IR Boundaries

`Line[]` (tokenizer output) → `Ast` (parser output: schema, templates, tables) → `[]ResolvedTable` (templates merged) → `ResolvedAst` (passes applied) → `TypedAst` (SQL type strings resolved, modifiers as booleans) → SQL string

### Key Design Patterns

- **Generator Registry** (`generator.zig`): `Generator` struct (name, description, extension, category, dialects, version, author, generate fn ptr) + `REGISTRY` array + `get(name)` lookup + `listDetailed()` for rich output + `check()` for health validation. Generator implementations live in `generators/<name>.zig`. Adding a new generator = create `generators/<name>.zig` + add entry to `REGISTRY`. The CLI dispatches via `generator.get(name)` — no main.zig modification needed. The `extension` field specifies the output file extension (e.g. `.prisma`, `.sql`, `.json`) used in batch mode. The `category` field indicates schema-based vs standalone generators. The `dialects` field lists supported dialects (null = dialect-agnostic). The `version` and `author` fields provide metadata for display. The `dialect` parameter enables dialect-specific output. Current generators: `json-schema` (standalone, agnostic), `sql-ddl` (all 6 dialects), `prisma` (agnostic), `docs` (agnostic), `drizzle` (mysql/pg/sqlite), `typeorm` (mysql/pg/sqlite/mssql), `sqlalchemy` (mysql/pg/sqlite), `knex` (mysql/pg/sqlite/mssql), `openapi` (mysql/pg/sqlite/mssql/oracle), `graphql` (agnostic), `symbol-index` (all 6 dialects).

- **DialectBackend vtable** (`dialect/dialect.zig`): 33 function pointers (26 required + 7 optional) + 3 behavioral flags + 1 data field (`quoteChar`) for dialect-specific SQL rendering and type mapping. `getBackend()` returns `*const DialectBackend` (pointer to static const, avoids 136-byte copy). Includes `lookupSym` (SS symbol → SqlType) and `quoteChar` for forward mapping and diff output. `codegen/codegen.zig` is fully dialect-agnostic (zero `switch(dialect)` in production code). Per-dialect: `dialect/mysql.zig`, `dialect/pg.zig`, `dialect/sqlite.zig`, `dialect/mssql.zig`, `dialect/oracle.zig`, `dialect/db2.zig`; shared logic in `dialect/common.zig`. Adding a new SQL dialect = new enum variant + new `dialect/<name>.zig` (~300 lines, self-contained type mapping). Comptime validation via `comptimeValidateAllPointers()` auto-validates all function pointer fields.

- **CompileConfig** (`pipeline/forward.zig`): Configuration struct for the compile handler, replacing 13 positional parameters. All fields have named defaults; callers specify only what they need. Used by `handleCompileRequest(io, alloc, cfg)` in `pipeline/handlers.zig`.

- **PipelineOptions** (`pipeline/forward.zig`): Configuration struct for the unified compilation pipeline. Replaces three separate functions (`compilePipeline`, `compilePipelineVerbose`, `compilePipelineWithImports`) with a single `compilePipeline(alloc, file_data, opts)`. Fields: `io`, `import_ctx`, `resolve_imports`, `merge_imports`, `run_semantic`, `verbose_passes`, `json_errors`.

- **DiffConfig / MigrateConfig** (`pipeline/diff.zig`, `pipeline/migrate.zig`): Configuration structs for diff and migrate handlers, replacing 8-11 positional parameters each. Follows the `CompileConfig` pattern. `handleDiff(io, alloc, DiffConfig)`, `handleMigrate(io, alloc, MigrateConfig)`, and `handleReverse(io, alloc, file_data, ReverseConfig)` are the unified entry points.

- **FormatConfig / ExportConfig / StatsConfig** (`pipeline/handlers.zig`): Configuration structs for format, export, and stats handlers, replacing 5-7 positional parameters each. Follows the `CompileConfig` pattern. All handlers now use `io_mod.writeOutput` for consistent I/O instead of mixing `std.debug.print` and `io_mod.writeOutput`.

- **Config Merge** (`config_merge.zig`): Extracted from `main.zig` for testability. `mergeCliConfig(parsed, cfg)` merges CLI flags with config file defaults (CLI takes precedence). Handles 7 merge cases: dialect, quiet, json_errors, color, target, stream, parallel. Each case has unit tests verifying precedence semantics.

- **`generateFromSchema`** (`pipeline/handlers.zig`): Shared helper that handles the full compile→generate→write pipeline. Used by both `rune generate` and `rune docs` in `main.zig`, eliminating duplicate dispatch logic.

- **Export Command** (`pipeline/handlers.zig`): `handleExport()` compiles a schema and exports it as structured data (JSON, text, or Markdown) for tooling integration. JSON export includes schema metadata, table names, field counts, index counts, and FK counts. Text export provides a concise summary. Markdown export generates a table documentation with field types.

- **CLI Unknown-Flag Detection** (`cli.zig`): Unrecognized `--` flags produce `error.UnknownFlag` with the flag name in the error message, instead of silently treating them as file paths. Known flags are checked against `GLOBAL_FLAG_REGISTRY` (20 entries in `cli/flag_registry.zig`) plus `KNOWN_FLAGS` for subcommand-specific flags.

- **Table-Driven Subcommand Dispatch** (`cli.zig`): Subcommand routing uses a comptime `parsers` array of `{name, parse_fn}` entries. Adding a new subcommand = add an entry to `COMMAND_REGISTRY` + add a `parseXxxArgs` function + add an entry to the `parsers` table.

- **Table-Driven LSP Method Dispatch** (`lsp/server.zig`): LSP method routing uses a `DISPATCH_TABLE` array of `{method, handler}` entries. Each handler has a uniform signature `(self, stdout, id, params)`. Adding a new LSP method = add entry to `DISPATCH_TABLE` + add handler in `lsp/handlers.zig`. Eliminates the 22-branch if-else chain that previously existed in the `run()` method.

- **Data-Driven Lint Rule Dispatch** (`lint/rules.zig`): Lint rule execution uses a `RULES` array of `{rule, handler}` entries. Each handler receives the full AST + config and iterates over relevant entities (tables, custom types, or entire schema). Handlers are organized into category modules: `lint/handlers/structural.zig` (7 rules), `lint/handlers/naming.zig` (8 rules), `lint/handlers/validation.zig` (5 rules), `lint/handlers/compat.zig` (3 rules), `lint/handlers/fk.zig` (5 rules), `lint/handlers/index.zig` (3 rules), `lint/handlers/view.zig` (3 rules), `lint/handlers/enum.zig` (4 rules). Adding a new lint rule = add entry to `RULES` + implement handler function in appropriate module. Replaces 22 repetitive guard-then-call blocks with a single loop.

- **FlagRegistry** (`cli/flag_registry.zig`): All 20 global CLI flags defined once in `GLOBAL_FLAG_REGISTRY` array. `matchesFlag()` matches long and short forms. `isKnownGlobalFlag()` provides unknown-flag detection. `parseGlobalFlags` uses `matchesFlag` for boolean flag detection instead of raw `std.mem.eql` chains.

- **Semantic Pass Manager** (`semantic/pass_manager.zig`): `PassContext` + `SemanticPass` interface + `DEFAULT_PASSES` array. Pass implementations in `semantic/pass/*.zig` (17 passes). `semantic/analyzer.zig` orchestrates template resolution + pass execution. Dependency ordering validated at comptime. Each pass declares its access pattern via `PassAccess` struct (`reads_tables`, `writes_tables`, `modifies_table_list`, `writes_types`). `--verbose-passes` CLI flag prints pass execution details. New passes: create `semantic/pass/<name>.zig` with `pub fn run(ctx: *PassContext) !void` and add to `DEFAULT_PASSES`.

- **ResolvedAst IR** (`types/resolved_ast.zig`): `ResolvedTable` + `ResolvedAst` — output of template resolution + semantic passes. `ResolvedTable` includes `template_ref` for tracking which template was applied. Separated from `types/ast.zig` (parser output) for clean IR boundary. Re-exported from `ast.zig` for backward compatibility.

- **TypedAst IR** (`types/typed_ast.zig`): Separates type resolution from code generation. Codegen only outputs strings — no type inference logic.

- **TypeInfo Methods** (`types/ast.zig`): `TypeInfo` carries embedded `isNumeric()`, `isString()`, `isDatetime()`, `isBoolean()`, `isBlob()`, `isOther()` methods that classify SS type symbols. Collocates type behavior with the type definition — no external lookup tables needed for classification.

- **Template Slot Merging** (`semantic/template.zig`): Template inheritance with `...` slot controls field insertion order. Merge formula: `parent_before + child_before + <concrete> + child_after + parent_after`. Max 4 parents via mixin syntax (`+`).

- **Conditional Schema Blocks** (`parser/parser.zig`, `semantic/pass/resolve_conditionals.zig`): `@if(dialect=pg|sqlite)` ... `@endif` blocks within table definitions allow dialect-specific fields. Fields inside the block are only included when compiling for a matching dialect. The parser records conditional blocks in `Table.conditional_blocks`, and the `resolve_conditionals` semantic pass filters them based on the target dialect. The pass runs after `resolve_names` and before `autofk`.

- **Schema Version Directive** (`parser/parser.zig`, `types/ast.zig`): `@version X.Y.Z` declares schema version metadata. The version flows through the pipeline (AST → ResolvedAst → TypedAst) and is emitted as a SQL comment (`-- Schema version: X.Y.Z`) after the header. Used for forward/backward compatibility tracking and schema evolution.

- **Multi-Error Recovery** (`pipeline/import_resolver.zig`, `types/ast.zig`): Parser records all syntax errors via `DiagnosticCollector` and returns a partial AST with `error_count` field. `tokenizeAndParseWithLines` always returns the tree (even with errors), enabling the pipeline to report all errors in one pass. When `error_count > 0`, the AST is partial (some tables/templates may be missing). Future: semantic analysis on partial ASTs for additional error discovery.

- **Self-contained SqlType** (`types/sql_type.zig`): `SqlType.toSql()` delegates to `DialectBackend.renderType` for dialect-aware rendering. `toJsonSchema()` provides dialect-agnostic JSON Schema output.

- **Dialect-Aware Diff** (`diff/semantic.zig`): Unified type equivalence module — `typeInfoEquiv` (AST-level TypeInfo comparison) and `semanticEquiv` (SQL string-level via reverse lookup). Canonical SS symbol mapping ensures different symbols resolving to the same SQL type are equivalent (e.g. `N4` ↔ `4`), but distinct types like `n` (int) vs `N` (bigint) are NOT equivalent.

- **Two-Pass FK Diffing** (`diff/fks.zig`): First pass matches identical FKs (structure + actions). Second pass matches structurally identical FKs with different actions → `modify`. Remaining unmatched FKs → `drop`/`add`.

- **Reverse Lookup Vtable**: `DialectBackend.reverseLookup` (optional) allows dialect-specific reverse engineering (e.g. SQLite's heuristic-based INTEGER/TEXT disambiguation). Fallback to general `reverse/map.zig` matching when vtable is null. The general path uses comptime iteration over `DIALECT_NAMES` to match all dialects via `REVERSE_MAP` data, with case-insensitive parameterized type matching for Oracle (`VARCHAR2(N)`, `NUMBER(P,S)`) and Db2 (`DECIMAL(P,S)`, `VARCHAR(N)`). Reverse mapping data lives in `types/reverse_map.zig` (canonical location), consumed by both `reverse/map.zig` and `diff/semantic.zig`. Adding a new dialect requires only 3 changes: add to `Dialect` enum, add struct field to `DialectTypeMap`, add case to `getDialectType()`.

- **Weighted Confidence Scoring** (`reverse/map.zig`): `computeConfidence(base_score, col_name)` applies naming-convention bonuses to base confidence scores from REVERSE_MAP or hardcoded values. Bonuses: +5 for snake_case, +3 for semantic suffixes (`_id`, `_at`, `_on`, `_name`), +3 for boolean prefixes (`is_`, `has_`, `can_`). Scores capped at 100. Applied in `reverseLookup` to all code paths (REVERSE_MAP match, parameterized types, ENUM, unknown, SQLite vtable).

- **Unified ReverseResult** (`dialect/dialect.zig`): Single `ReverseResult` struct shared by dialect backends and `reverse/column.zig` — zero duplication across the reverse pipeline.

- **Shared Generator Test Helpers** (`generators/common_test.zig`): Centralized test utilities (`makeTestTable`, `makeTestTableWithFks`, `makeTestTableWithIndexes`, `makeTestAst`, `makeTestAstWithName`, `makeTestColumn`, `makeTestColumnWithFlags`) used by all 10 generator `*_test.zig` files. Eliminates ~120 lines of duplicated helper definitions. Each test file imports from `common_test.zig` instead of defining its own copy.

- **ORM Default Formatter** (`generators/common.zig`): `OrmTarget` enum + `getOrmFormatter()` factory returns pre-configured `DefaultFormatter` for each ORM (drizzle, knex, sqlalchemy, typeorm). Shared callbacks (`formatStringSingleQuoted`, `jsBoolTrue`/`jsBoolFalse`/`jsNull`) eliminate ~60 lines of duplicated callback functions across 4 ORM generators.

- **Migration Plan IR** (`diff/plan.zig`): Explicit intermediate representation between `SchemaDiff` and SQL generation. `MigrationPlan` struct contains `operations: []Operation` where each `Operation` is a tagged union (`drop_table`, `create_table`, `alter_table`, `drop_view`, `create_view`, `modify_view`). `planFromDiff()` converts diffs to plans, `invertPlan()` transforms plans for rollback. The existing `generateFromDiff` and `generateRollback` functions delegate through the plan layer, producing identical output while enabling future dry-run inspection and plan-level validation.

- **Parallel Table Compilation** (`codegen/parallel.zig`): Dependency analysis and concurrent compilation for independent tables using `std.Thread`. `analyzeDependencies()` builds a `DepGraph` from FK references, `topoSort()` produces a valid compilation order, and `compileParallel()` generates SQL in topological order with threaded compilation for independent table groups. Each thread uses its own arena allocator for thread safety. BufferPool provides thread-safe buffer reuse across parallel compilation threads (mutex-protected acquire/release). Falls back to sequential for schemas with <10 tables or fully-dependent tables. CLI flag: `--parallel` (used with `--stream`).

### Module Roles

| Directory | Module | Role |
|-----------|--------|------|
| `pipeline/` | `forward.zig` | `.ss` → SQL compilation pipeline (tokenizer → parser → semantic → ResolvedAst) |
| | `handlers.zig` | CLI output handlers (compile, stats, generate, docs, format, export) |
| | `validation.zig` | Validation handlers (validate, check) with summary output |
| | `reverse.zig` | SQL → `.ss` orchestration + dialect auto-detection |
| | `diff.zig` | Diff pipeline orchestration (`rune diff` handler) |
| | `migrate.zig` | Migrate pipeline orchestration (`rune migrate` handler) |
| | `stats.zig` | Schema statistics (field type classification, table/field/view/constraint counts) |
| `lsp/` | `protocol.zig` | JSON-RPC message types and LSP protocol helpers |
| | `documents.zig` | Document state manager (open/change/close tracking) |
| | `compile_service.zig` | Pipeline wrapper for LSP diagnostics + TypedAst capture (dialect-aware) |
| | `server.zig` | LSP server main loop (JSON-RPC over stdio) |
| | `features.zig` | LSP interactive features (document symbols, completion, hover, go-to-definition, code actions, formatting, inlay hints, code lens) |
| `parser/` | `parser.zig` | Token-level `.ss` parser → AST, dispatches to parse_* modules |
| | `parse_field.zig` | Field declaration parsing (type, modifiers, default, inline FK) |
| | `parse_fk.zig`, `parse_check.zig`, `parse_index.zig` | FK/Check/Index parsing |
| | `parse_template.zig`, `parse_table.zig` | Template and table header parsing |
| | `parse_recovery.zig` | Forward parser error recovery |
| | `sql_parser.zig` | Recursive-descent SQL DDL parser (reverse pipeline) |
| | `sql_parser_helpers.zig` | Identifier/literal parsing, expression parser |
| | `sql_parser_create.zig`, `sql_parser_alter.zig`, etc. | SQL sub-statement parsing |
| `codegen/` | `codegen.zig` | TypedAst → SQL DDL text, orchestrates column/index/constraint emission |
| | `columns.zig` | Column definition rendering |
| | `indexes.zig` | Inline and standalone index emission |
| | `streaming.zig` | Streaming compilation (emit each table independently) |
| | `parallel.zig` | Parallel table compilation (dependency analysis + concurrent codegen) |
| `dialect/` | `dialect.zig` | DialectBackend vtable + getBackend() + ReverseResult |
| | `enum.zig` | Dialect enum (mysql, pg, sqlite, mssql, oracle) |
| | `mysql.zig`, `pg.zig`, `sqlite.zig`, `mssql.zig`, `oracle.zig`, `db2.zig` | Per-dialect backend implementations |
| | `common.zig` | Shared PG/SQLite dialect functions |
| | `sqlite_hints.zig` | SQLite type affinity hints + column heuristics |
| `reverse/` | `codegen.zig` | SQL → `.ss` orchestration |
| | `column.zig` | Column reverse engineering |
| | `map.zig` | Reverse lookup logic (imports shared data from `types/reverse_map.zig`) |
| | `map_data.zig` | Re-exports `types/reverse_map.zig` (backward-compatible shim) |
| | `fk.zig`, `check.zig` | FK/Check constraint reverse engineering |
| | `template_extraction.zig` | Template extraction from SQL |
| `diff/` | `engine.zig` | Table-level diff engine |
| | `types.zig` | SchemaDiff, TableDiff, FieldDiff, CustomTypeDiff data structures |
| | `plan.zig` | Migration Plan IR — intermediate representation between diff and SQL |
| | `fields.zig` | Field-level diffing + rename detection |
| | `fks.zig` | FK diffing — two-pass matching |
| | `indexes.zig` | Index diffing |
| | `rename.zig` | Shared rename-adjustment logic for index/FK field name substitution |
| | `format.zig` | Diff output formatting — re-exports from sub-modules |
| | `format_common.zig` | Shared diff format helpers (formatTypeInfo) |
| | `format/text.zig` | Text diff output (human-readable `-- ALTER TABLE` format) |
| | `format/json.zig` | JSON diff output (structured, machine-readable) |
| | `format/sarif.zig` | SARIF diff output (CI/CD integration, versioned from `version.zig`) |
| | `format/markdown.zig` | Markdown diff output (PR descriptions, documentation) |
| | `semantic.zig` | Dialect-aware type equivalence (`typeInfoEquiv` + `semanticEquiv`) |
| | `migrate.zig` | Migration SQL generation with `MigrationContext` struct (bundles shared state for emit functions) |
| `types/` | `ast.zig` | AST type definitions (Schema, Table, Field, Template, etc.) |
| | `resolved_ast.zig` | ResolvedTable + ResolvedAst (semantic output) |
| | `typed_ast.zig` | TypedAst IR + ColumnFlags bitflags |
| | `sql_type.zig` | Self-contained SqlType union with toSql()/toJsonSchema() |
| | `type_registry.zig` | Thin delegation to DialectBackend.lookupSym (forward type mapping) |
| | `type_resolver.zig` | TypeResolver namespace — ResolvedAst → TypedAst type resolution |
| | `symbol_table.zig` | Schema-level symbol table for name resolution |
| | `reverse_map.zig` | Shared REVERSE_MAP data (52+ entries) + ReverseMapping struct with extensible DialectTypeMap (`DIALECT_NAMES` comptime array + `getDialectType()` accessor) |
| `semantic/` | `analyzer.zig` | SemanticAnalyzer + diagnosticTrace |
| | `pass_manager.zig` | PassContext + SemanticPass + DEFAULT_PASSES + validateDependencyOrder |
| | `trace.zig` | Shared AST trace formatting |
| | `diagnostic.zig` | Multi-error diagnostic collector (printAll, formatJson, formatLsp, formatTerminal) |
| | `template.zig` | Template inheritance resolution |
| | `pass/*.zig` | 17 semantic passes (autofk, resolve_names, resolve_conditionals, suffix_inference, validate, template_type_conflict, validate_unused_enums, etc.) |
| root | `main.zig` | CLI entry point, command dispatch |
| | `config_merge.zig` | Config merge logic (CLI flags + config file defaults) |
| | `wasm.zig` | WASM library entry point (exports rune_compile, rune_diff, rune_migrate, rune_reverse, rune_lint, rune_format, rune_tune, rune_generate, rune_export, rune_docs, rune_stats, rune_validate, rune_version, rune_last_error, rune_last_error_code, rune_reset) |
| | `lint.zig` | Lint barrel — re-exports from `lint/rules.zig` (49 rules + `RuleInfo` + `RULE_INFO`), `lint/handlers/*.zig` (8 handler modules), `lint/format.zig` (text/JSON/SARIF), `lint/config.zig` (LintConfig, LintRule enum with `name()`, `description()`, `isFixable()`, TOML parsing), `lint/fix.zig` (auto-fix for 11 rules) |
| | `cli/lint_cmd.zig` | Lint CLI handler (extracted from main.zig) |
| | `cli/errors.zig` | CLI error handling (extracted from main.zig) |
| | `cli.zig` | Argument parsing, Command/ParsedArgs types |
| | `io.zig` | File I/O, stdin reading, output writing, memory-mapped I/O |
| | `bench.zig` | Benchmark entry point |
| | `color.zig` | ANSI color output (ColorMode, writeColorized) |
| | `version.zig` | Centralized version constant |
| generators | `generators/json_schema.zig` | JSON Schema generator (draft-07) |
| | `generators/sql_ddl.zig` | SQL DDL generator (wraps codegen) |
| | `generators/common.zig` | Shared generator helpers + ORM default formatter factory + SQL type-to-string writer |
| | `generators/common_test.zig` | Shared test utilities for all generator test files |
| | `generators/prisma.zig` | Prisma schema generator |
| | `generators/docs.zig` | Markdown documentation generator |
| | `generators/drizzle.zig` | Drizzle ORM TypeScript schema generator |
| | `generators/typeorm.zig` | TypeORM entity class generator |
| | `generators/sqlalchemy.zig` | SQLAlchemy ORM model generator |
| | `generators/knex.zig` | Knex.js migration file generator |
| | `generators/openapi.zig` | OpenAPI 3.1 specification generator |
| | `generators/graphql.zig` | GraphQL type definitions generator |

### Testing

- **Unit tests**: Zig `test` blocks in dedicated `*_test.zig` colocated files alongside production modules. 109 colocated test files wired via `tests.zig` comptime index. Only `diff/fields.zig` and `semantic/pass/*.zig` retain inline tests (private helpers / pass implementations). Run via `zig build test`
- **Golden tests**: Shell scripts compile `.ss` files and `diff` against `.sql` golden files in `tests/expected/`. Version comments are stripped before comparison for version-resilient testing. 30 scripts. Golden test utilities: `golden_test.zig` (stripVersion, compareOutput). Run via `bash tests/test.sh` or `zig build golden-tests`
- Test data: `.ss` input files in `tests/`, expected output in `tests/expected/`, error recovery inputs in `tests/error-recovery/`, diff test pairs in `tests/diff/`, reverse test pairs in `tests/reverse/`

## Conventions

- Zig 0.16+, formatted with `zig fmt`
- Line endings: LF, 4-space indent for `.zig`/`.yml`, 2-space for `.md`/`.sh`/`.sql`
- All modules take `std.mem.Allocator` (arena-style, command-lifetime memory)
- Parser is fail-fast on syntax errors; semantic analyzer collects multiple diagnostics
