# Rune Type System Reference

Rune uses single-character symbols to represent SQL types. Each symbol compiles to the appropriate type for the target dialect (MySQL, PostgreSQL, or SQLite).

## Core Type Symbols

| Symbol | MySQL | PostgreSQL | SQLite | Description |
|--------|-------|-----------|--------|-------------|
| `n` | `int` | `integer` | `INTEGER` | 32-bit integer |
| `N` | `bigint` | `bigint` | `INTEGER` | 64-bit integer |
| `i` | `smallint` | `smallint` | `INTEGER` | 16-bit integer |
| `m` | `decimal(16,2)` | `numeric(16,2)` | `NUMERIC(16,2)` | Money (2 decimal places) |
| `M` | `decimal(20,6)` | `numeric(20,6)` | `NUMERIC(20,6)` | High-precision decimal |
| `s` | `varchar(255)` | `varchar(255)` | `TEXT` | Short string |
| `S` | `text` | `text` | `TEXT` | Long text |
| `b` | `boolean` | `boolean` | `INTEGER` | Boolean |
| `B` | `blob` | `bytea` | `BLOB` | Binary data |
| `j` | `json` | `json` | `TEXT` | JSON text |
| `J` | `jsonb` | `jsonb` | `TEXT` | Binary JSON (PostgreSQL) |
| `I` | `varchar(45)` | `inet` | `TEXT` | IP address |
| `d` | `date` | `date` | `TEXT` | Date only |
| `t` | `datetime` | `timestamp` | `TEXT` | Date + time |
| `T` | `timestamp` | `timestamptz` | `TEXT` | Timestamp with timezone |
| `U` | `char(36)` | `uuid` | `TEXT` | UUID |
| `p` | `int` | `serial` | `INTEGER` | Auto-incrementing integer |

## Parameterized Types

### Variable-Length Strings

| Syntax | Type | Example |
|--------|------|---------|
| `s` | varchar(255) | `name s` |
| `s64` | varchar(64) | `code s64` |
| `s128` | varchar(128) | `token s128` |
| `s0` | TEXT (unlimited) | `bio s0` |

### Decimal Precision

| Syntax | Type | Example |
|--------|------|---------|
| `m` | decimal(16,2) | `price m` |
| `16,2` | decimal(16,2) | `price 16,2` |
| `10,4` | decimal(10,4) | `rate 10,4` |
| `20,6` | decimal(20,6) | `amount M` |

### Explicit Integer Width

| Syntax | Type | Example |
|--------|------|---------|
| `16` | int (16-bit) | `flags 16` |
| `32` | int (32-bit) | `count 32` |

### Enum Types

| Syntax | Type | Example |
|--------|------|---------|
| `e('a','b','c')` | ENUM | `status e('active','inactive')` |

MySQL renders as `ENUM('active','inactive')`. PostgreSQL and SQLite render as `TEXT` with a `CHECK (col IN (...))` constraint.

## Unsigned Integers

Prefix `+` on integer symbols adds `UNSIGNED` (MySQL only; PostgreSQL and SQLite ignore it):

| Syntax | MySQL | PostgreSQL | SQLite |
|--------|-------|-----------|--------|
| `+n` | `int unsigned` | `integer` | `INTEGER` |
| `+N` | `bigint unsigned` | `bigint` | `INTEGER` |
| `+i` | `smallint unsigned` | `smallint` | `INTEGER` |

## Custom Type Definitions

Define reusable type aliases with the `~` directive:

```
~ type_name base_type [dialect=type ...]
```

Examples:
```
~ uuid n mysql=char(36) pg=uuid sqlite=TEXT
~ money m
~ email s256
~ status e('active','inactive','suspended')
```

Custom types resolve at compile time. Dialect overrides apply only when compiling for that dialect.

### Resolution Rules

1. Single-char symbols (`n`, `N`, etc.) are looked up in the dialect's symbol table
2. Multi-char types (`s128`, `16,2`) are parsed as parameterized types
3. Unknown identifiers are treated as custom type references
4. Custom types can reference other custom types (max depth: 32)
5. Dialect overrides take precedence over the base type

## Type Resolution Flow

```
.ss symbol → TypeInfo → SqlType → DialectBackend.renderType → SQL string
```

1. **Parse**: The tokenizer/parser produces a `TypeInfo` from the SS symbol
2. **Resolve**: `SqlType.fromTypeInfo()` converts `TypeInfo` to the dialect-agnostic `SqlType`
3. **Render**: Each dialect backend's `renderType()` produces the final SQL type string

## Dialect Behavior

### MySQL
- `uuid` → `char(36)` (not a native type)
- `inet` → `varchar(45)`
- `boolean` → `boolean`
- `jsonb` → `json` (no binary JSON)
- `timestamptz` → `timestamp` (no timezone type)
- `serial` → `int` (uses AUTO_INCREMENT instead)
- Supports `UNSIGNED` prefix on integers
- Supports `ENUM('a','b')` native syntax

### PostgreSQL
- `uuid` → `uuid` (native type)
- `inet` → `inet` (native type)
- `blob` → `bytea`
- `jsonb` → `jsonb` (native binary JSON)
- `timestamptz` → `timestamptz` (native type)
- `serial` → `serial` (native auto-increment)
- `enum_values` → `TEXT` + `CHECK (col IN (...))`

### SQLite
- All integer types → `INTEGER` (affinity-based)
- All string types → `TEXT`
- All datetime types → `TEXT`
- `boolean` → `INTEGER` (0/1)
- `blob` → `BLOB`
- `decimal(P,S)` → `NUMERIC(P,S)`
- `enum_values` → `TEXT` + `CHECK (col IN (...))`

SQLite overrides these symbols from the default map:
- `N` → `INTEGER` (instead of `bigint`)
- `U` → `TEXT` (passthrough, instead of `uuid`)
- `p` → `INTEGER` (passthrough, instead of `serial`)

## JSON Schema Output

The `rune generate json-schema` command produces JSON Schema (draft-07) from `.ss` files. Each `SqlType` maps to JSON Schema properties:

| SqlType | JSON Schema |
|---------|-------------|
| int, bigint, smallint, serial | `{ "type": "integer" }` |
| decimal, varchar | `{ "type": "number" }` / `{ "type": "string" }` |
| text, blob, json, uuid, inet, date, datetime, timestamptz | `{ "type": "string" }` |
| boolean | `{ "type": "boolean" }` |
| enum_values | `{ "enum": [...] }` |
