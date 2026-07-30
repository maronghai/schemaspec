# Rune Schema Language Reference

Rune uses `.ss` files to declare database schemas with a minimal, symbol-based syntax. A single-character symbol represents each SQL type, and structural markers (`#`, `%`, `$`, etc.) define schema elements.

## Quick Example

```ss
$ myapp utf8mb4 autofk

% timestamps
  created_at t
  updated_at t
  ...

# users
  id n++
  name s*
  email s@u
  status e('active','inactive') = 'active'
  org_id > orgs. -C
  age [0,150]
  created_at t
```

Compiles to MySQL:
```sql
CREATE TABLE users (
  id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name varchar(255) NOT NULL,
  email varchar(255),
  status ENUM('active','inactive') DEFAULT 'active',
  org_id int,
  age int CHECK (age BETWEEN 0 AND 150),
  created_at datetime,
  UNIQUE INDEX idx_email (email),
  FOREIGN KEY (org_id) REFERENCES orgs(id) ON DELETE CASCADE
) ENGINE=InnoDB;
```

## Schema Declaration

The `$` line declares schema-level settings.

```
$ schema_name [charset] [autofk]
```

| Part | Description |
|------|-------------|
| `schema_name` | Schema identifier (used in documentation output) |
| `charset` | Default character set (e.g., `utf8mb4`) |
| `autofk` | Enable automatic FK inference from `_id` suffix fields |

Examples:
```
$ myapp
$ myapp utf8mb4
$ myapp utf8mb4 autofk
```

## Custom Type Definitions

The `~` line creates reusable type aliases.

```
~ type_name base_type [dialect=type ...]
```

Examples:
```
~ uuid n mysql=char(36) pg=uuid sqlite=TEXT mssql=UNIQUEIDENTIFIER
~ money m
~ status e('active','inactive','suspended')
~ password s256
```

Custom types resolve at compile time. Dialect overrides apply only to the specified dialect.

## Templates

Templates are reusable field sets with inheritance and a slot mechanism.

```
% template_name [> parent1 + parent2]
  field declarations...
  ...
```

The `...` (slot) marker controls where child fields are inserted:

```
% timestamps
  created_at t
  updated_at t
  ...
```

Template inheritance merges fields using the slot:
- Parent fields before `...` → child fields before concrete → child fields after concrete → parent fields after `...`

Max 4 parent templates via mixin syntax (`+`).

## Table Declarations

```
# [template_ref] table_name [: comment] [^ engine]
```

| Part | Description |
|------|-------------|
| `#` | Table marker |
| `template_ref` | Optional template to inherit fields from |
| `table_name` | The table name |
| `: comment` | Table comment (emitted as SQL comment) |
| `^ engine` | Storage engine (e.g., `^InnoDB`, `^MyISAM`) |

Examples:
```
# users
# base users : user accounts table
# base users ^InnoDB
# users ^ : with comment
```

## Field Declarations

```
field_name [type] [modifiers] [=default] [check] [> fk] [: comment]
```

### Type Symbols

See [type.md](type.md) for the complete type reference.

| Symbol | MySQL | PostgreSQL | SQLite | MSSQL |
|--------|-------|-----------|--------|-------|
| `n` | int | integer | INTEGER | INT |
| `N` | bigint | bigint | INTEGER | BIGINT |
| `i` | smallint | smallint | INTEGER | SMALLINT |
| `m` | decimal(16,2) | numeric(16,2) | NUMERIC(16,2) | NUMERIC(16,2) |
| `M` | decimal(20,6) | numeric(20,6) | NUMERIC(20,6) | NUMERIC(20,6) |
| `s` | varchar(255) | varchar(255) | TEXT | NVARCHAR(255) |
| `S` | text | text | TEXT | NVARCHAR(MAX) |
| `b` | boolean | boolean | INTEGER | BIT |
| `B` | blob | bytea | BLOB | VARBINARY(MAX) |
| `j` | json | json | TEXT | NVARCHAR(MAX) |
| `J` | jsonb | jsonb | TEXT | NVARCHAR(MAX) |
| `I` | inet | inet | TEXT | NVARCHAR(45) |
| `d` | date | date | TEXT | DATE |
| `t` | datetime | timestamp | TEXT | DATETIME2 |
| `T` | timestamptz | timestamptz | TEXT | DATETIMEOFFSET |
| `U` | char(36) | uuid | TEXT | UNIQUEIDENTIFIER |
| `p` | int | serial | INTEGER | INT |

Multi-char types: `s128` = varchar(128), `16,2` = decimal(16,2), `e('a','b')` = enum.

### Modifiers

| Modifier | Meaning | Example |
|----------|---------|---------|
| `++` | Auto-increment primary key | `id n++` |
| `+` | Auto-increment | `seq n+` |
| `!` | Primary key | `id n!` |
| `*` | NOT NULL | `name s*` |
| `@u` | Inline unique index | `email s@u` |
| `@` | Inline index | `name s@` |
| `+n`, `+N`, `+i` | Unsigned (MySQL only) | `flags +n` |

Modifiers can fuse with types: `n++`, `s128*`, `n!`

### Default Values

```
field = value
```

| Default | Example |
|---------|---------|
| NULL | `name =NULL` |
| Number | `age =0` |
| String | `status ='active'` |
| Timestamp | `created_at =CURRENT_TIMESTAMP` |

### CHECK Constraints

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[a,b]` | BETWEEN a AND b | `age [0,150]` |
| `[a,b)` | a <= x < b | `score [0,100)` |
| `(a,b]` | a < x <= b | `ratio (0,1]` |
| `(a,b)` | a < x < b | `temp (-40,50)` |
| `{v1,v2}` | IN list | `status {A,B,C}` |
| `{>0}` | Comparison | `price {>0}` |

### Inline Foreign Keys

```
field > ref_table.ref_field [actions]
```

| Syntax | Meaning |
|--------|---------|
| `> table.field` | FK to specific column |
| `> table.` | FK to table, infer ref from local name |
| `> users` | Ultra shorthand: local=`user_id`, ref=`users.id` |

FK Actions:
| Suffix | Meaning |
|--------|---------|
| `-C` | ON DELETE CASCADE |
| `-N` | ON DELETE SET NULL |
| `C` | ON UPDATE CASCADE |
| `N` | ON UPDATE SET NULL |

Examples:
```
user_id > users.id
org_id > orgs.
> users
category_id > categories.id -C N
```

### Generated Columns

```
field AS (expression) [VIRTUAL|STORED]
```

Example:
```
full_name AS (first_name + ' ' + last_name) STORED
```

## Standalone Foreign Keys

```
> local_field ref_table[.ref_field] [actions]
```

Same syntax as inline FKs but on its own line.

## Index Declarations

```
@ [u|f] [index_name] (field1, field2, ...)
```

| Prefix | Type |
|--------|------|
| (none) | Regular index |
| `u` | Unique index |
| `f` | Fulltext index |

Suffix `-` on field name = descending order.

Examples:
```
@ email
@ u email
@ f body
@ idx_users_email (email)
@ (user_id, created_at)
@ u (email, status)
@ idx_sort (name-, created_at-)
```

## Composite Primary Key

```
! field1, field2, ...
```

Example:
```
! user_id, role_id
```

## Views

```
& view_name = SQL query
```

Example:
```
& active_users = SELECT * FROM users WHERE active = 1
```

## Imports

```
@import path/to/file.ss
```

Imports are resolved at compile time. Circular imports are detected and reported as errors. Max import depth: 8.

## Comments

| Syntax | Behavior |
|--------|----------|
| `-- text` | SQL comment (emitted in output) |
| `; text` | Spec comment (ignored entirely) |
| `: text` | Field/table comment (emitted as SQL comment) |
