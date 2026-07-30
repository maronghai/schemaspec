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
name      s32 *                            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
email     s128 *                             COMMENT='用户表';
balance   m =0
```

## The Problem

Database schema DDL is verbose. A simple user table takes 15+ lines of SQL with repetitive type declarations, modifier keywords, and boilerplate constraints. Schema changes require hand-writing ALTER TABLE statements. Cross-dialect support means maintaining parallel SQL files. And there's no good way to express reusable table patterns.

## The Solution

Rune is a minimal DSL that compresses database schema declarations into single-character symbols. One symbol = one SQL type. Modifiers fuse multiple keywords into postfix notation. Templates eliminate repetition. The compiler handles dialect differences — write once, generate MySQL/PostgreSQL/SQLite/MSSQL.

**Average compression: 3-5x per field** — common declarations shrink dramatically.

| Rune | Raw SQL | Savings |
|------|---------|---------|
| `id n++` | `int AUTO_INCREMENT PRIMARY KEY` | 30 chars |
| `balance m =0` | `decimal(16, 2) DEFAULT 0` | 24 chars |
| `create_at +` | `datetime DEFAULT CURRENT_TIMESTAMP` | 34 chars |
| `email s128 *` | `varchar(128) NOT NULL` | 21 chars |
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

name      s32 *
email     s128 *
password  s256 *
balance   m =0

@u email
@ name

#base order  ^MyISAM  : 订单表

order_no    s64 *
user_id               ; suffix _id → int
amount      m *

> user_id user.id     ; foreign key
```

**2. Generate SQL**:

```bash
cd rune && zig build
./rune/zig-out/bin/rune myapp.ss              # MySQL (default)
./rune/zig-out/bin/rune myapp.ss -d pg        # PostgreSQL
./rune/zig-out/bin/rune myapp.ss -d sqlite    # SQLite
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

| Symbol | MySQL | PostgreSQL | Description |
|--------|-------|-----------|-------------|
| `n` | int | integer | 32-bit integer |
| `N` | bigint | bigint | 64-bit integer |
| `i` | smallint | smallint | 16-bit integer |
| `m` | decimal(16,2) | numeric(16,2) | Standard currency |
| `M` | decimal(20,6) | numeric(20,6) | High-precision currency |
| `s` | varchar(255) | varchar(255) | Default string |
| `s\d+` | varchar(n) | varchar(n) | Explicit length |
| `S` | text | text | Unlimited text |
| `b` | boolean | boolean | True/false |
| `B` | blob | bytea | Binary data |
| `j` / `J` | json / json | json / jsonb | JSON / binary JSON |
| `d` / `t` / `T` | date / datetime / timestamp | date / timestamp / timestamptz | Temporal |
| `U` | char(36) | uuid | UUID |
| `p` | int | serial | Auto-increment |
| `I` | varchar(45) | inet | IP address |
| `e(...)` | ENUM('...') | text + CHECK | Enumeration |

**Suffix inference** — no type symbol needed: `_id` → int, `_on` → date, `_at` → datetime, *(none)* → varchar(255). Explicit type always wins.

### Modifiers

| Symbol | Meaning | Example |
|--------|---------|---------|
| `++` | AUTO_INCREMENT PK / CURRENT_TIMESTAMP ON UPDATE | `id n++` / `ts ++` |
| `+` | AUTO_INCREMENT / CURRENT_TIMESTAMP | `seq n+` / `ts +` |
| `!` | PRIMARY KEY | `code s32!` |
| `*` | NOT NULL | `name s32 *` |
| `=` / `*=` | DEFAULT / NOT NULL + DEFAULT | `status 1 =0` |
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
name s32 *              ; → id, name, version, create_at, update_at
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

- **DialectBackend vtable**: 26+6 function pointers + 1 data field (`quoteChar`). Zero `switch(dialect)` in codegen or type mapping. Adding a dialect = new `dialect_<name>.zig` (~200 lines, self-contained type mapping). Vtable organized into 6 logical sections: Shared, Forward, Alter, TypeMapping, Optional, and Behavioral flags.
- **Semantic Pass Manager**: 8 dependency-ordered passes with access pattern declarations (`reads_tables`, `writes_tables`, `modifies_table_list`, `writes_types`). New pass = new `pass/<name>.zig`. `canRunConcurrently()` detects parallelization opportunities.
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

17 core symbols, 4 dialect backends, lossless roundtrip for MySQL/PG, metadata-preserved roundtrip for SQLite. Adding a new dialect is a local change — implement `lookupSym` + `renderType` + `quoteChar` in one file.

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

Type differences: `b` → `BIT`, `t` → `DATETIME2`, `B` → `VARBARCHAR(MAX)`, `s` → `NVARCHAR(255)`. Identifiers use square brackets `[name]`.

### Migration

```bash
rune migrate old.ss new.ss                          # → ALTER TABLE SQL
rune migrate old.ss new.ss -d pg -o migration.sql   # to file
rune migrate old.ss new.ss --target json-schema     # → structured JSON
```

Detects: new/dropped tables, added/dropped/modified/renamed columns, index changes, FK changes. All wrapped in transaction. JSON output produces an `operations` array with typed entries (`drop_table`, `create_table`, `add_column`, etc.) and dialect metadata.

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
rune generate docs schema.ss          # → Markdown documentation
rune generate --list                  # → list available generators
```

8 built-in generators: JSON Schema, SQL DDL, Prisma, Drizzle ORM, TypeORM, SQLAlchemy, Knex, and Markdown docs. All generators are dialect-aware — pass `-d pg` for PostgreSQL-specific output.

## Roadmap

- [ ] LSP language server (completion, diagnostics, go-to-definition)
- [ ] Oracle dialect support
- [x] Microsoft SQL Server dialect support
- [ ] IBM Db2 dialect support
- [x] JSON Schema output for API layer generation
- [x] Prisma schema output
- [x] Drizzle ORM schema output
- [x] TypeORM entity class output
- [x] SQLAlchemy ORM model output
- [x] Knex.js migration file output
- [ ] Incremental migration (only changed tables)

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
