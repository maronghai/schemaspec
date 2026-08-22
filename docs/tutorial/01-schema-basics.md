# Lesson 1: Schema Basics

**Duration**: 10 minutes

## Objective

Learn the fundamental building blocks of a Rune schema: schema declaration, tables, fields, type symbols, and modifiers.

## The `.ss` File Format

Rune schemas live in `.ss` files (Schema Source). Each line declares one construct.

```ss
```

[▶ Open in Playground](../../playground/index.html#JCBteWFwcCB1dGY4bWI0IGF1dG9mawoKIyB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMAogIGVtYWlsIHNAdQogIGFjdGl2ZSBiID0gdHJ1ZQogIGNyZWF0ZWRfYXQgdA)

Compile it:
```bash
rune schema.ss -o schema.sql
```

Output (MySQL):
```sql
CREATE TABLE users (
  id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name varchar(100) NOT NULL,
  email varchar(255) NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Schema Declaration (`$`)

```
$ schema_name [charset] [autofk]
```

| Part | Required | Description |
|------|----------|-------------|
| `schema_name` | Yes | Identifier for documentation/generators |
| `charset` | No | Default charset (e.g., `utf8mb4`) |
| `autofk` | No | Enable automatic FK inference from `_id` suffix |

```ss
```

[▶ Open in Playground](../../playground/index.html#JCBibG9nCiQgYmxvZyB1dGY4bWI0CiQgYmxvZyB1dGY4bWI0IGF1dG9maw)

## Table Declaration (`#`)

```
# [template] table_name [: comment] [^ engine]
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwojIGJhc2UgdXNlcnMgOiB1c2VyIGFjY291bnRzIHRhYmxlCiMgdXNlcnMgXklubm9EQg)

## Field Declaration

```
field_name [type] [modifiers] [=default] [check] [> fk] [: comment]
```

### Type Symbols (Core 17)

| Symbol | Meaning | MySQL | PostgreSQL |
|--------|---------|-------|------------|
| `n` | 32-bit integer | `int` | `integer` |
| `N` | 64-bit integer | `bigint` | `bigint` |
| `i` | 16-bit integer | `smallint` | `smallint` |
| `s` | varchar(255) | `varchar(255)` | `varchar(255)` |
| `s64` | varchar(64) | `varchar(64)` | `varchar(64)` |
| `S` | text (unbounded) | `text` | `text` |
| `b` | boolean | `boolean` | `boolean` |
| `t` | datetime | `datetime` | `timestamp` |
| `T` | timestamptz | `timestamp` | `timestamptz` |
| `d` | date | `date` | `date` |
| `m` | decimal(16,2) | `decimal(16,2)` | `numeric(16,2)` |
| `M` | decimal(20,6) | `decimal(20,6)` | `numeric(20,6)` |
| `B` | blob | `blob` | `bytea` |
| `j` | json | `json` | `json` |
| `J` | jsonb | `json` | `jsonb` |
| `U` | uuid | `char(36)` | `uuid` |
| `p` | serial/auto-inc | `int` | `serial` |

### Modifiers

| Modifier | Fused Example | Meaning |
|----------|---------------|---------|
| `++` | `n++` | Auto-increment PRIMARY KEY |
| `+` | `n+` | Auto-increment (not PK) |
| `!` | `n!` | PRIMARY KEY (no auto-inc) |
| `?` | `s?` | Nullable (fields are NOT NULL by default) |
| `@u` | `s@u` | Inline UNIQUE index |
| `@` | `s@` | Inline regular index |

### Default Values

```ss
```

## Exercise

Create `exercise1.ss`:
```ss
```

[▶ Open in Playground](../../playground/index.html#JCBzaG9wIHV0ZjhtYjQKCiMgcHJvZHVjdHMKICBpZCBuKysKICBza3UgczMyQHUKICBuYW1lIHMyMDAKICBwcmljZSBtCiAgZGVzY3JpcHRpb24gUz8KICBhY3RpdmUgYiA9IHRydWUKICBjcmVhdGVkX2F0IHQ)

Compile and verify:
```bash
rune exercise1.ss -d mysql
rune exercise1.ss -d pg
rune exercise1.ss -d sqlite
```

## Key Takeaways

- `.ss` files are line-oriented; first character determines construct type
- Fields are `NOT NULL` by default — use `?` for nullable
- Type symbols are single characters; parameterized with digits (`s100`, `16,2`)
- Modifiers fuse with types: `n++`, `s100?`, `s@u`
- Same `.ss` compiles to idiomatic SQL for all 6 dialects

---

**Next**: [Lesson 2: Custom Types →](02-custom-types.md)
