# Rune

A minimal DSL for declaring database schemas using single-character symbols. Compiles `.ss` schema files into SQL DDL (MySQL, PostgreSQL, SQLite, MSSQL), and supports reverse engineering, schema diff, and migration generation.

## Quick Start

```bash
cd rune && zig build                              # Build
./zig-out/bin/rune schema.ss                      # Compile to MySQL DDL
./zig-out/bin/rune schema.ss -d pg                # Compile to PostgreSQL
./zig-out/bin/rune schema.ss -d sqlite            # Compile to SQLite
./zig-out/bin/rune migrate old.ss new.ss          # Generate migration SQL
./zig-out/bin/rune reverse schema.sql             # Reverse SQL to .ss
./zig-out/bin/rune reverse schema.sql --format json  # Reverse SQL to JSON
./zig-out/bin/rune stats schema.ss                # Print schema statistics
./zig-out/bin/rune diff old.ss new.ss             # Show schema differences
./zig-out/bin/rune docs schema.ss                 # Generate Markdown docs
```

## Commands

| Command | Usage | Description |
|---------|-------|-------------|
| *(default)* | `rune [input.ss]` | Compile `.ss` to SQL DDL |
| `validate` | `rune validate [input.ss]` | Validate schema without output |
| `check` | `rune check [input.ss]` | Check schema validity (exit 1 on error) |
| `stats` | `rune stats [input.ss]` | Print schema statistics with field type breakdown (numeric/string/datetime/boolean/other) |
| `diff` | `rune diff <old.ss> <new.ss>` | Show schema differences |
| `migrate` | `rune migrate <old.ss> <new.ss>` | Generate ALTER TABLE migration SQL |
| `reverse` | `rune reverse [input.sql]` | Reverse SQL DDL to `.ss` schema (supports `--format json`) |
| `docs` | `rune docs [input.ss]` | Generate Markdown documentation |
| `generate` | `rune generate <gen> [input.ss]` | Run a code generator (`json-schema`, `sql-ddl`, `prisma`, `docs`, `drizzle`, `typeorm`, `sqlalchemy`, `knex`, `openapi`) |

## Flags Reference

### General

| Flag | Short | Description |
|------|-------|-------------|
| `-d`, `--dialect` | | Target SQL dialect: `mysql` (default), `pg`, `sqlite`, `mssql` |
| `--target` | | Output format: `sql` (default), `json-schema` |
| `-o` | | Write output to file instead of stdout |
| `-v`, `--version` | | Print version and exit |
| `-h`, `--help` | | Show help message and exit |

### Compilation

| Flag | Short | Description |
|------|-------|-------------|
| `--trace` | | Print intermediate pipeline stages for debugging |
| `--stats` | `-s` | Print compilation statistics (table/field counts) |
| `--check` | | Validate schema without writing output (exit 1 on error) |
| `--strict` | | Treat warnings as errors (for CI/CD) |
| `--verbose-passes` | | Print semantic pass execution details |
| `--import-path` | | Additional search path for `@import` directives |
| `-q`, `--quiet` | | Suppress non-essential output |

**Note**: Unrecognized `--` flags produce an error with the flag name, instead of being silently treated as file paths.

### Diff / Migrate / Reverse

| Flag | Description |
|------|-------------|
| `--format text\|json\|sarif` | Output format for diff/migrate/reverse results |
| `--check` | Exit with code 1 if differences exist (CI gate) |
| `--dry-run` | Show migration SQL without writing to file |
| `--rollback` | Generate rollback SQL instead of forward migration |

### Reverse Engineering

| Flag | Description |
|------|-------------|
| `-T` | Extract shared templates from SQL |
| `--format json` | Output reverse-engineered schema as structured JSON |

## Testing

```bash
# Run all unit tests (51 colocated test files, 558+ tests)
zig build test

# Build only
zig build

# Build with optimizations
zig build -Doptimize=ReleaseSafe

# Check formatting
zig fmt --check src/
```

Tests use Zig's built-in `test` blocks with `std.testing` allocator. Each source module has a colocated `*_test.zig` file wired via `src/tests.zig`.

## Architecture

For deep dives into the codebase architecture, IR boundaries, dialect backend vtable, semantic pass manager, and module roles, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Project Structure

```
rune/src/
  main.zig, cli.zig, io.zig         # CLI entry point + argument parsing
  generator.zig                      # generator registry (pluggable, dialect-aware)
  generators/                        # generator implementations
    common.zig                       #   shared generator utilities + DefaultFormatter
    json_schema.zig                  #   JSON Schema output
    sql_ddl.zig                      #   SQL DDL output
    prisma.zig                       #   Prisma schema output
    docs.zig                         #   Markdown documentation output
    drizzle.zig                      #   Drizzle ORM output
    typeorm.zig                      #   TypeORM entity output
    sqlalchemy.zig                   #   SQLAlchemy ORM output
    knex.zig                         #   Knex.js migration output
  pipeline/    forward.zig, reverse.zig, diff.zig, import_resolver.zig
  parser/      tokenizer.zig, parser.zig, parse_*.zig, sql_parser*.zig
  codegen/     codegen.zig, columns.zig, indexes.zig
  dialect/     dialect.zig, mysql.zig, pg.zig, sqlite.zig, mssql.zig, common.zig
  reverse/     codegen.zig, column.zig, map.zig, fk.zig, check.zig
  diff/        engine.zig, fields.zig, fks.zig, indexes.zig, migrate.zig, migrate_helpers.zig
  types/       ast.zig, resolved_ast.zig, typed_ast.zig, sql_type.zig, ...
  semantic/    analyzer.zig, pass_manager.zig, pass/*.zig

rune/grammar.ebnf    # Formal EBNF grammar for the .ss language
rune/schema.md       # Language reference (syntax, constructs, examples)
rune/type.md         # Type system reference (symbols, dialects, custom types)
```

## Contributing

- **Language**: Zig 0.16+, formatted with `zig fmt`
- **Line endings**: LF
- **Indent**: 4-space for `.zig`, 2-space for `.md`/`.sh`/`.sql`
- **Memory model**: Arena-style allocator per command lifetime
- **Tests**: All changes must pass `zig build` + `zig build test`
- **New dialects**: Add `dialect/<name>.zig` (~200 lines, self-contained type mapping)
