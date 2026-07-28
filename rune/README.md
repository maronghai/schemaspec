# Rune

A minimal DSL for declaring database schemas using single-character symbols. Compiles `.ss` schema files into SQL DDL (MySQL, PostgreSQL, SQLite), and supports reverse engineering, schema diff, and migration generation.

## Quick Start

```bash
cd rune && zig build                              # Build
./zig-out/bin/rune schema.ss                      # Compile to MySQL DDL
./zig-out/bin/rune schema.ss -d pg                # Compile to PostgreSQL
./zig-out/bin/rune schema.ss -d sqlite            # Compile to SQLite
./zig-out/bin/rune migrate old.ss new.ss          # Generate migration SQL
./zig-out/bin/rune reverse schema.sql             # Reverse SQL to .ss
./zig-out/bin/rune diff old.ss new.ss             # Show schema differences
./zig-out/bin/rune docs schema.ss                 # Generate Markdown docs
```

## Commands

| Command | Usage | Description |
|---------|-------|-------------|
| *(default)* | `rune [input.ss]` | Compile `.ss` to SQL DDL |
| `validate` | `rune validate [input.ss]` | Validate schema without output |
| `diff` | `rune diff <old.ss> <new.ss>` | Show schema differences |
| `migrate` | `rune migrate <old.ss> <new.ss>` | Generate ALTER TABLE migration SQL |
| `reverse` | `rune reverse [input.sql]` | Reverse SQL DDL to `.ss` schema |
| `docs` | `rune docs [input.ss]` | Generate Markdown documentation |

## Flags Reference

### General

| Flag | Short | Description |
|------|-------|-------------|
| `-d`, `--dialect` | | Target SQL dialect: `mysql` (default), `pg`, `sqlite` |
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

### Diff / Migrate

| Flag | Description |
|------|-------------|
| `--format text\|json\|sarif` | Output format for diff/migrate results |
| `--check` | Exit with code 1 if differences exist (CI gate) |
| `--dry-run` | Show migration SQL without writing to file |
| `--rollback` | Generate rollback SQL instead of forward migration |

### Reverse Engineering

| Flag | Description |
|------|-------------|
| `-T` | Extract shared templates from SQL |

## Testing

```bash
# Run all test suites
bash tests/test_coverage.sh

# Or run individual suites
bash tests/test.sh                  # MySQL golden (86 tests)
bash tests/test_postgres.sh         # PostgreSQL golden (85 tests)
bash tests/test_sqlite.sh           # SQLite golden (25 tests)
bash tests/test_migrate.sh          # Migration golden (34 tests)
bash tests/test_diff.sh             # Diff golden (12 tests)
bash tests/test_reverse.sh          # Reverse engineering (15 tests)
bash tests/test_error_recovery.sh   # Error recovery (12 tests)
bash tests/test_json_schema.sh      # JSON Schema (3 tests)
bash tests/test_roundtrip.sh        # Round-trip fidelity (26 tests)
bash tests/test_imports.sh          # Import system (6 tests)
bash tests/test_stdin.sh            # Stdin pipeline (4 tests)
bash tests/test_reverse_confidence.sh # Reverse confidence (4 tests)

# Run a single test by name filter
bash tests/test.sh 01               # Run tests matching "01"
```

## Architecture

For deep dives into the codebase architecture, IR boundaries, dialect backend vtable, semantic pass manager, and module roles, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Project Structure

```
rune/src/
  main.zig, cli.zig, io.zig         # CLI entry point + argument parsing
  pipeline/    forward.zig, reverse.zig, diff.zig   # Pipeline orchestration
  parser/      tokenizer.zig, parser.zig, parse_*.zig, sql_parser*.zig
  codegen/     codegen.zig, columns.zig, indexes.zig
  dialect/     dialect.zig, mysql.zig, pg.zig, sqlite.zig, common.zig
  reverse/     codegen.zig, column.zig, map.zig, fk.zig, check.zig
  diff/        engine.zig, fields.zig, fks.zig, indexes.zig, migrate.zig
  types/       ast.zig, resolved_ast.zig, typed_ast.zig, sql_type.zig, ...
  semantic/    analyzer.zig, pass_manager.zig, pass/*.zig
```

## Contributing

- **Language**: Zig 0.16+, formatted with `zig fmt`
- **Line endings**: LF
- **Indent**: 4-space for `.zig`, 2-space for `.md`/`.sh`/`.sql`
- **Memory model**: Arena-style allocator per command lifetime
- **Tests**: All changes must pass `zig build` + `bash tests/test_coverage.sh`
- **New dialects**: Add `dialect/<name>.zig` (~200 lines, self-contained type mapping)
