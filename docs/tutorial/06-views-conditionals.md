# Lesson 6: Views & Conditional Schemas

**Duration**: 15 minutes

## Objective

Learn view declarations and dialect-conditional schema blocks.

## Views

```
& view_name = SQL query
& view_name = SQL query UNION ALL SQL query
```

### Basic View

```ss
# users
  id n++
  name s100
  email s255@u
  active b = true
  created_at t

& active_users = SELECT id, name, email FROM users WHERE active = 1
```

### Set Operations

```ss
& all_accounts = SELECT id, name, 'user' AS type FROM users
  UNION ALL
  SELECT id, name, 'admin' AS type FROM admins

& common_roles = SELECT role FROM user_roles
  INTERSECT
  SELECT role FROM admin_roles

& unique_to_users = SELECT role FROM user_roles
  EXCEPT
  SELECT role FROM admin_roles
```

Supported: `UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT` (top-level, outside string literals).

### View Compilation

Views compile to dialect-appropriate `CREATE VIEW`:

```sql
-- MySQL
CREATE VIEW active_users AS SELECT id, name, email FROM users WHERE active = 1;

-- PostgreSQL
CREATE VIEW active_users AS SELECT id, name, email FROM users WHERE active = true;
```

> **Note**: Views are read-only in Rune. Use `rune reverse` to extract views from existing databases.

## Conditional Schema Blocks

```
@if(dialect=pg|sqlite)
  field_name type
@endif
```

Fields inside `@if` blocks are only included when compiling for matching dialects.

### Syntax

| Part | Description |
|------|-------------|
| `@if(dialect=...)` | Start conditional block |
| `dialect_list` | Pipe-separated: `pg`, `mysql`, `sqlite`, `mssql`, `oracle`, `db2` |
| `@endif` | End conditional block |

### Example: Dialect-Specific Features

```ss
# users
  id n++
  name s100
  email s255@u

@if(dialect=pg)
  bio t
  avatar B
  search_vector j
@endif

@if(dialect=mysql)
  bio S
  avatar B
@endif

@if(dialect=sqlite)
  bio S
  avatar B
@endif

  status s16 = 'active'
```

### Compile for Different Dialects

```bash
rune schema.ss -d pg    # includes bio, avatar, search_vector
rune schema.ss -d mysql # includes bio, avatar
rune schema.ss -d sqlite # includes bio, avatar
```

### Nested Conditionals

```ss
@if(dialect=pg|mysql)
  @if(dialect=pg)
    pg_only_field t
  @endif
  shared_field n
@endif
```

> **Note**: Conditionals are resolved after template merging, before type resolution.

## Schema Version Directive

```
@version X.Y.Z
```

Emitted as SQL comment:
```sql
-- Schema version: 1.2.0
```

Flows through AST → ResolvedAst → TypedAst for forward/backward compatibility tracking.

## Exercise

Create `exercise6.ss`:
```ss
$ analytics utf8mb4

@version 2.1.0

# events
  id n++
  user_id n > users.id
  event_type s64
  payload j
  created_at t

@if(dialect=pg)
  search_vec j
  geo_point I
@endif

@if(dialect=mysql|sqlite)
  geo_lat n
  geo_lng n
@endif

# users
  id n++
  email s255@u
  name s100

& recent_events = SELECT e.*, u.email
  FROM events e
  JOIN users u ON e.user_id = u.id
  WHERE e.created_at > NOW() - INTERVAL 7 DAY

& event_types = SELECT DISTINCT event_type FROM events
```

Compile for all dialects:
```bash
for d in mysql pg sqlite mssql oracle db2; do
  echo "=== $d ==="
  rune exercise6.ss -d $d | grep -E "(CREATE VIEW|search_vec|geo_)" | head -5
done
```

## Key Takeaways

- Views: `& name = query` with `UNION/ALL/INTERSECT/EXCEPT`
- Conditionals: `@if(dialect=pg|mysql)` ... `@endif`
- Dialect list: `mysql`, `pg`, `sqlite`, `mssql`, `oracle`, `db2`
- Fields outside conditionals always included
- `@version X.Y.Z` → `-- Schema version: X.Y.Z` SQL comment
- Conditionals resolved after templates, before type resolution
- Use for: PG-only features (JSONB, tsvector), MySQL-specific types, SQLite affinity

---

**Next**: [Lesson 7: Code Generators →](07-generators.md)
