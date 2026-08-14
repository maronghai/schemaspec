# Rune

> One character = one type. Convention over configuration. Template-driven.

```
$ ecommerce                              CREATE DATABASE `ecommerce`;

% base
id n++
...                                        CREATE TABLE `user` (
version   N                                `id`    int AUTO_INCREMENT PRIMARY KEY,
status    1 =0                             `name`  varchar(32) NOT NULL,
create_at +                                `email` varchar(128) NOT NULL,
update_at ++                               `balance` decimal(16, 2) DEFAULT 0,
                                            `version` bigint,
#base user  : 用户表                       `status`  int(1) DEFAULT 0,
                                            ...
name      s32                             ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
email     s128                               COMMENT='用户表';
balance   m =0
```

## The Problem

Database schema DDL is verbose. A simple user table takes 15+ lines of SQL with repetitive type declarations, modifier keywords, and boilerplate constraints. Schema changes require hand-writing ALTER TABLE statements. Cross-dialect support means maintaining parallel SQL files. And there's no good way to express reusable table patterns.

## The Solution

Rune is a minimal DSL that compresses database schema declarations into single-character symbols. One symbol = one SQL type. Modifiers fuse multiple keywords into postfix notation. Templates eliminate repetition. The compiler handles dialect differences — write once, generate MySQL/PostgreSQL/SQLite/MSSQL/Oracle/Db2.

**Average compression: 3-5x per field** — common declarations shrink dramatically.

| Rune | Raw SQL | Savings |
|------|---------|---------|
| `id n++` | `int AUTO_INCREMENT PRIMARY KEY` | 30 chars |
| `balance m =0` | `decimal(16, 2) DEFAULT 0` | 24 chars |
| `create_at +` | `datetime DEFAULT CURRENT_TIMESTAMP` | 34 chars |
| `email s128` | `varchar(128) NOT NULL` | 10 chars |
| `@ name` | `INDEX idx_name (name)` | 71% savings |
| `> user.id` | `FOREIGN KEY (user_id) REFERENCES user(id)` | 76% savings |

## Quick Example

**1. Write a schema** (`myapp.ss`):

```asm
$ myapp

% base
id n++
...
version   N
status    1 =0
create_at +
update_at ++

#base user  : 用户表

name      s32
email     s128
password  s256
balance   m =0

@u email
@ name

#base order  ^MyISAM  : 订单表

order_no    s64
user_id               ; suffix _id → int
amount      m

> user_id user.id     ; foreign key
```

**2. Generate SQL**:

```bash
cd rune && zig build
./rune/zig-out/bin/rune myapp.ss              # MySQL (default)
./rune/zig-out/bin/rune myapp.ss -d pg        # PostgreSQL
./rune/zig-out/bin/rune myapp.ss -d sqlite    # SQLite

```

> **Note (WSL2 / mounted filesystems):** if the source tree lives on a DrvFS mount (`/mnt/c`,
> `/mnt/e`, ...), Zig's `.zig-cache` rename/lock ops fail with `AccessDenied` and the build is
> slow and broken. Set the cache to a native Linux path first:
>
> ```bash
> export ZIG_LOCAL_CACHE_DIR=~/.cache/zig-rune
> export ZIG_GLOBAL_CACHE_DIR=~/.cache/zig-rune-global
> ```
>
> A clean Debug build then succeeds in ~20s (vs 53s + failure) and incremental rebuilds ~1.5s.
```

**3. Output**:

```sql
CREATE TABLE `user` (
  `id`       int AUTO_INCREMENT PRIMARY KEY,
  `name`     varchar(32) NOT NULL,
  `email`    varchar(128) NOT NULL,
  `password` varchar(256) NOT NULL,
  `balance`  decimal(16, 2) DEFAULT 0,
  `version`  bigint,
  `status`   int(1) DEFAULT 0,
  `create_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `update_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX `uk_email` (`email`),
  INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

## Core Concepts

### Type System

One character = one type. Case matters.

| Symbol | MySQL | PostgreSQL | Oracle | Description |
|--------|-------|-----------|--------|-------------|
| `n` | int | integer | NUMBER(10) | 32-bit integer |
| `N` | bigint | bigint | NUMBER(19) | 64-bit integer |
| `i` | smallint | smallint | NUMBER(5) | 16-bit integer |
| `m` | decimal(16,2) | numeric(16,2) | NUMBER(16,2) | Standard currency |
| `M` | decimal(20,6) | numeric(20,6) | NUMBER(20,6) | High-precision currency |
| `s` | varchar(255) | varchar(255) | VARCHAR2(255) | Default string |
| `s\d+` | varchar(n) | varchar(n) | VARCHAR2(n) | Explicit length |
| `S` | text | text | CLOB | Unlimited text |
| `b` | boolean | boolean | NUMBER(1) | True/false |
| `B` | blob | bytea | BLOB | Binary data |
| `j` / `J` | json / json | json / jsonb | CLOB | JSON / binary JSON |
| `d` / `t` / `T` | date / datetime / timestamp | date / timestamp / timestamptz | DATE / TIMESTAMP / TIMESTAMP WITH TIME ZONE | Temporal |
| `U` | char(36) | uuid | RAW(16) | UUID |
| `p` | int | serial | NUMBER(10) | Auto-increment |
| `I` | varchar(45) | inet | VARCHAR2(45) | IP address |
| `e(...)` | ENUM('...') | text + CHECK | VARCHAR2 + CHECK | Enumeration |

**Suffix inference** — no type symbol needed: `_id` → int, `_on` → date, `_at` → datetime, *(none)* → varchar(255). Explicit type always wins.

### Modifiers

| Symbol | Meaning | Example |
|--------|---------|---------|
| `++` | AUTO_INCREMENT PK / CURRENT_TIMESTAMP ON UPDATE | `id n++` / `ts ++` |
| `+` | AUTO_INCREMENT / CURRENT_TIMESTAMP | `seq n+` / `ts +` |
| `!` | PRIMARY KEY | `code s32!` |
| `=` | DEFAULT | `status 1 =0` |
| `+n` / `+N` | UNSIGNED | `count +n` |
| `@` / `@u` | INDEX / UNIQUE INDEX | `name s32 @` |
| `[...]` | CHECK constraint | `age n [0,150]` |
| `:` | COMMENT | `name s32 : 用户名` |

### Foreign Keys

```asm
user_id     > user.id                      ; inline FK
> user_id user.id                          ; standalone
> user.id                                  ; ultra shorthand (infers user_id)
> user_id user.id -C C                     ; ON DELETE/UPDATE CASCADE
> coupon_id coupon.id -N C                 ; SET NULL + CASCADE
```

Actions: `-C` delete cascade, `-N` delete set null, `C` update cascade, `N` update set null.

### Indexes

```asm
@ name                  ; INDEX idx_name (name)
@u email                ; UNIQUE INDEX uk_email (email)
@ idx_name (a, b)       ; full syntax for composite
```

### CHECK Constraints

```asm
age     n [0,150]       ; BETWEEN (inclusive)
age     n (0,150)       ; exclusive bounds
status  1 {0,1,2}       ; IN list
amount  m {>0}           ; comparison
```

### Comments

```asm
; internal note          ; stripped from output
-- SQL comment           ; passed to DDL
: 表注释                  ; becomes COMMENT clause
```

### Templates

Templates define reusable table patterns. The `...` slot controls where concrete fields are inserted.

```asm
% base
id n++
...
version   N
create_at +
update_at ++

#base user
name s32              ; → id, name, version, create_at, update_at
```

Templates support inheritance (`% audit > base`) and mixins (`% mixed base + soft_delete`).

### Views

```asm
& active_users = SELECT id, name FROM user WHERE active = 1
```

### Custom Types

```asm
$ mydb
  ~ uuid s36                    ; varchar(36) everywhere
  ~ email s128                  ; varchar(128) everywhere
  ~ ip_addr mysql=s45 pg=inet   ; dialect-specific
```

## Configuration

Create a `rune.toml` in your project root to set defaults:

```toml
[project]
name = "myapp"

[dialect]
default = "pg"

[output]
color = "auto"
quiet = false
```

CLI flags always override config values. Use `--config <path>` to specify a custom config file.

## Architecture

### Compiler Pipeline

```
.ss → Tokenizer → Parser → Template Resolution → Semantic Passes → Type Resolver → Codegen → SQL
```

Three IR boundaries: `Line[]` → `Ast` → `ResolvedAst` → `TypedAst` → SQL string.

### Three Pipelines

1. **Forward**: `.ss` → SQL DDL
2. **Reverse**: SQL DDL → `.ss` (with optional template extraction)
3. **Diff/Migrate**: Two `.ss` files → ALTER TABLE migration SQL

### Key Design

- **DialectBackend vtable**: 25 required + 7 optional function pointers + 3 behavioral flags + 1 data field (`quoteChar`). Zero `switch(dialect)` in codegen or type mapping. Adding a dialect = new `dialect_<name>.zig` (~200 lines, self-contained type mapping). Vtable organized into 6 logical sections: Shared, Forward, Alter, TypeMapping, Optional, and Behavioral flags.
- **Semantic Pass Manager**: 17 dependency-ordered passes with access pattern declarations (`reads_tables`, `writes_tables`, `modifies_table_list`, `writes_types`). New pass = new `pass/<name>.zig`. Cross-table index name collision detection (v0.125.0).
- **Import Cache**: Memoized import resolution prevents re-parsing the same file when imported by multiple parents.
- **AST-level diff**: Semantic comparison, not text diff. Detects renames, type changes, structural differences.

### Type Mapping

Vtable-driven, zero hardcoded dialect switches:

```
SS symbol → DialectBackend.lookupSym (per-dialect SqlType)
                ↓
       DialectBackend.renderType (SQL string)
                ↓
       DialectBackend.quoteChar (diff output)
                ↕
       reverse_map (SQL → SS, for reverse pipeline)
```

17 core symbols, 6 dialect backends, lossless roundtrip for MySQL/PG, metadata-preserved roundtrip for SQLite. Adding a new dialect is a local change — implement `lookupSym` + `renderType` + `quoteChar` in one file.

## Testing

Rune has two test tiers: **unit tests** (Zig `test` blocks) and **golden tests** (shell scripts that compile `.ss` files and `diff` against expected `.sql` output). Run everything at once with the coverage runner:

```bash
bash tests/test_coverage.sh           # all suites
bash tests/test_coverage.sh --quick   # skip benchmark regression
```

### Unit Tests

Zig `test` blocks in colocated `*_test.zig` files alongside their production modules. 118 test files wired via `tests.zig` comptime index.

```bash
cd rune && zig build test             # run all unit tests
```

### Golden Tests

Shell scripts compile `.ss` input files and compare output against golden files in `tests/expected/`. Version comments (`-- Generated by rune X.Y.Z`) are stripped automatically for version-resilient comparison.

```bash
bash tests/test.sh                    # MySQL (85 tests)
bash tests/test_postgres.sh           # PostgreSQL (86 tests)
bash tests/test_sqlite.sh             # SQLite (26 tests)
bash tests/test_mssql.sh              # MSSQL (26 tests)
bash tests/test_oracle.sh             # Oracle (103 tests)
bash tests/test_db2.sh                # Db2 (103 tests)
```

Run a single test by name substring filter:

```bash
bash tests/test.sh 01                 # tests matching "01"
bash tests/test.sh template           # tests matching "template"
```

### Feature Test Suites

| Suite | Tests | What it covers |
|-------|------:|----------------|
| Migration | 34 | `migrate old.ss new.ss`, `--rollback`, `--format json` |
| Migrate Status | 7 | `migrate status`, 4-digit prefixes, `--json-errors` |
| Diff | 12 | `rune diff`, `--format sarif`/`json`/`markdown`, `--check`, `--summary` |
| Reverse | 21 | SQL→`.ss` for MySQL/PG/SQLite |
| Reverse Oracle | 5 | Oracle reverse engineering |
| Reverse Db2 | 5 | Db2 reverse engineering |
| Error Recovery | 12 | Multi-error parsing, partial AST recovery |
| JSON Schema | 3 | `generate json-schema` with FK references and templates |
| OpenAPI | 3 | `generate openapi` (OpenAPI 3.1 spec) |
| GraphQL | 4 | `generate graphql` (type definitions) |
| Imports | 6 | `@import`, nested imports, circular detection, missing files |
| Stdin | 4 | `echo schema.ss \| rune`, `--check`, `-d pg` from stdin |
| Color | 5 | `--color always`/`never` ANSI output, diff summary |
| Validate | 4 | `rune validate`, `--stats` |
| Stats JSON | 3 | `rune stats --format json` |
| Init & Completions | 12 | `rune init`, `rune completions` for bash/zsh/fish/powershell |

### Roundtrip Tests

Tests the full pipeline: `.ss` → SQL → reverse → `.ss` → SQL. Verifies that the reverse-engineered `.ss` compiles to semantically equivalent SQL.

| Suite | Tests | Notes |
|-------|------:|-------|
| Roundtrip | 112 | 22 schemas × 5 dialects (MySQL, PG, SQLite, Oracle, Db2) |
| Property Roundtrip | 30+ | Random `.ss` schemas across 3 dialects, seed-reproducible |
| Reverse Confidence | 3 | Reverse lookup confidence scoring |

```bash
bash tests/test_roundtrip.sh                      # all roundtrip tests
bash tests/test_property_roundtrip.sh 30 42       # 30 iterations, seed=42
```

### Performance Tests

Benchmark regression testing with `--save`/`--check` mode. Compares current build performance against a saved baseline; exits with code 1 if any stage regresses more than 10%.

```bash
cd rune && zig build bench                 # run benchmark
cd rune && zig build bench -- --save       # save baseline
cd rune && zig build bench -- --check      # check for regressions
cd rune && zig build bench -- --dialect pg # benchmark PostgreSQL dialect
bash tests/test_bench.sh                   # golden test for bench CLI
```

### Parallel Test Runner

Runs 12 non-bench suites concurrently for faster CI:

```bash
bash tests/test_parallel.sh
```

### Shared Test Infrastructure

- **`tests/lib.sh`** — shared functions: `pass`, `fail`, `skip`, `header`, `summary`, `compare_files`, `strip_version` (auto-detects SQL/JSON/GraphQL version comments)
- **`tests/lib_parallel.sh`** — parallel suite runner: `run_suite_add`, `run_suite_run_all`, `run_suite_collect`
- **`tests/expected/`** — golden files (one `.sql`/`.json`/`.graphql` per test schema)
- **`tests/diff/`** — paired `.ss` files for diff/migrate tests
- **`tests/reverse/`** — SQL input files for reverse engineering tests
- **`tests/error-recovery/`** — intentionally broken `.ss` files for error recovery tests

### Adding a New Test

1. **Golden test**: Create `tests/new-test.ss`, compile it, save output to `tests/expected/new-test.sql`, add a run block to the appropriate `tests/test_*.sh` script.
2. **Unit test**: Create `tests/new_module_test.zig` with `test "description" { ... }`, add `@import` to `tests/tests.zig`.
3. **Roundtrip test**: Add the `.ss` filename to the `ROUNDTRIP_TESTS` array in `tests/test_roundtrip.sh`.

## Generators

### MySQL (default)

```bash
rune schema.ss                    # → MySQL DDL
rune schema.ss -d mysql           # explicit
```

### PostgreSQL

```bash
rune schema.ss -d pg              # → PostgreSQL DDL
rune schema.ss -d postgres        # alias
```

### SQLite

```bash
rune schema.ss -d sqlite          # → SQLite DDL
```

Type differences: `n` → `INTEGER`, `N` → `INTEGER`, `t` → `TEXT`, `U` → `TEXT`, `b` → `INTEGER`. SQLite emits `-- @sym` metadata comments for lossless roundtrip.

### Microsoft SQL Server

```bash
rune schema.ss -d mssql            # → MSSQL DDL
rune schema.ss -d sqlserver        # alias
```

Type differences: `b` → `BIT`, `t` → `DATETIME2`, `B` → `VARBINARY(MAX)`, `s` → `NVARCHAR(255)`. Identifiers use square brackets `[name]`.

### Oracle

```bash
rune schema.ss -d oracle           # → Oracle DDL
rune schema.ss -d ora              # alias
```

Type differences: `b` → `NUMBER(1)`, `t` → `TIMESTAMP`, `B` → `BLOB`, `s` → `VARCHAR2(255)`, `S` → `CLOB`. Uses double-quote identifiers, COMMENT ON for comments, and sequences for auto-increment.

### Migration

```bash
rune migrate old.ss new.ss                          # → ALTER TABLE SQL
rune migrate old.ss new.ss -d pg -o migration.sql   # to file
rune migrate old.ss new.ss --target json-schema     # → structured JSON
rune diff old.ss new.ss                             # → show schema differences
rune diff old.ss new.ss --color always              # → colored diff output
```

Detects: new/dropped tables, added/dropped/modified/renamed columns, index changes, FK changes. All wrapped in transaction. JSON output produces an `operations` array with typed entries (`drop_table`, `create_table`, `add_column`, etc.) and dialect metadata. Diff output supports colored terminal display with `--color auto|always|never`.

### Validate

```bash
rune validate schema.ss       # → exit 0 if valid, exit 1 if errors
rune validate < schema.ss     # also works from stdin
```

Standalone schema validation — runs the full semantic pipeline and reports diagnostics without producing SQL output. Useful for CI/CD checks and editor integration.

### Reverse Engineering

```bash
rune reverse schema.sql              # → .ss schema
rune reverse -t schema.sql           # with template extraction
rune reverse -d pg schema.sql        # PostgreSQL input
```

Handles: CREATE TABLE, PRIMARY KEY, indexes, FKs, CHECK constraints, ENUMs, views. Template extraction (`-t`) auto-discovers shared field patterns.

### Generate

```bash
rune generate json-schema schema.ss   # → JSON Schema (draft-07)
rune generate sql-ddl schema.ss       # → SQL DDL (CREATE TABLE)
rune generate prisma schema.ss        # → Prisma schema
rune generate drizzle schema.ss       # → Drizzle ORM TypeScript schema
rune generate typeorm schema.ss       # → TypeORM entity classes
rune generate sqlalchemy schema.ss    # → SQLAlchemy ORM models
rune generate knex schema.ss          # → Knex.js migration files
rune generate openapi schema.ss        # → OpenAPI 3.1 spec
rune generate graphql schema.ss        # → GraphQL type definitions
rune generate docs schema.ss          # → Markdown documentation
rune generate --list                  # → list available generators
rune generate schema.ss --generators prisma,drizzle,openapi  # → Batch generation
```

12 built-in generators: JSON Schema, SQL DDL, Prisma, Drizzle ORM, TypeORM, SQLAlchemy, Knex, OpenAPI 3.1, GraphQL, Markdown docs, and symbol-index. All generators are dialect-aware — pass `-d pg` for PostgreSQL-specific output. Batch generation runs multiple generators from a single compilation.

### Init

```bash
rune init                    # Create schema.ss with starter content
rune init myapp              # Create myapp.ss
rune init -o custom.ss       # Create custom.ss
rune init -d pg              # Create schema.ss with PostgreSQL hint
rune init --template blog    # Create blog schema (posts, categories, tags)
rune --init                  # Create schema.ss (flag equivalent)
```

Scaffolds a new project with a starter `.ss` file. Use `--template` to choose from preset schemas:

| Template | Description |
|----------|-------------|
| `default` | Users, posts, comments (default) |
| `blog` | Posts, categories, tags, comments |
| `ecommerce` | Products, orders, order_items, customers |
| `rest-api` | Resources, endpoints, API keys, audit log |

### Completions

```bash
rune completions bash        # → Bash completion script
rune completions zsh         # → Zsh completion script
rune completions fish        # → Fish completion script
rune completions powershell  # → PowerShell completion script
```

Install for your shell:
```bash
# Bash
source <(rune completions bash)

# Zsh
eval "$(rune completions zsh)"

# Fish
rune completions fish > ~/.config/fish/completions/rune.fish

# PowerShell
. $(rune completions powershell)
```

### Watch Mode

```bash
rune watch schema.ss                    # Watch and recompile on change (1s interval)
rune watch schema.ss --interval 500     # Watch with 500ms polling interval
rune watch schema.ss --parallel         # Watch with parallel compilation
rune watch schema.ss -d pg              # Watch and compile to PostgreSQL
rune watch schema.ss -o out.sql         # Watch and write to file
rune watch schema.ss -s                 # Watch with compilation stats
rune watch ./schemas --recursive        # Watch all .ss files in directory recursively

# Lint schema for quality issues (30 rules)
rune lint schema.ss                     # Check for PK, naming, FK indexes, timestamps, duplicates, circular FK (51 rules)
rune lint schema.ss --json-errors       # Lint as JSON (machine-readable)
rune lint schema.ss --strict            # Exit 1 if any warnings (CI/CD)
rune lint --show-rules                  # List all available rules
rune lint --init                        # Generate .rune-lint.toml config
```

Watch mode polls files for changes and automatically recompiles when modifications are detected. Use `--recursive` to watch an entire directory of `.ss` files — only changed files are recompiled. Press Ctrl+C to stop watching.

### Editor Integration

**VS Code** — Install the extension for syntax highlighting and commands:

```bash
cd packaging/vscode && code --install-extension .
```

**Any LSP-compatible editor** — Rune includes a built-in language server:

```bash
rune lsp    # Starts the LSP server over stdio
```

Features: diagnostics, completion, hover, go-to-definition, document symbols, references, highlights, rename, code actions, formatting, code lens.

## Roadmap

- [x] LSP language server (completion, diagnostics, hover, go-to-definition, document symbols, references, highlights, rename, code actions, formatting, code lens)
- [x] Oracle dialect support
- [x] Microsoft SQL Server dialect support
- [x] IBM Db2 dialect support
- [x] JSON Schema output for API layer generation
- [x] Prisma schema output
- [x] Drizzle ORM schema output
- [x] TypeORM entity class output
- [x] SQLAlchemy ORM model output
- [x] Knex.js migration file output
- [x] OpenAPI 3.1 spec output
- [x] Incremental migration (only changed tables) (v0.93.0)

## Vision

Rune starts as a schema DSL, but the long-term goal is a **universal database schema interchange format**. A single `.ss` file becomes the source of truth that generates:

- SQL DDL for any dialect
- Migration scripts for schema evolution
- ORM schemas (Prisma, Drizzle, SQLAlchemy)
- API validation rules (JSON Schema)
- Documentation (auto-generated from comments)

The schema file is the contract. Everything else is derived.

## License

[MIT](LICENSE)
