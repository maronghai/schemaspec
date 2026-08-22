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
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMAogIGVtYWlsIHMyNTVAdQogIGFjdGl2ZSBiID0gdHJ1ZQogIGNyZWF0ZWRfYXQgdAoKJiBhY3RpdmVfdXNlcnMgPSBTRUxFQ1QgaWQsIG5hbWUsIGVtYWlsIEZST00gdXNlcnMgV0hFUkUgYWN0aXZlID0gMQ)

### Set Operations

```ss
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
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMAogIGVtYWlsIHMyNTVAdQoKQGlmKGRpYWxlY3Q9cGcpCiAgYmlvIHQKICBhdmF0YXIgQgogIHNlYXJjaF92ZWN0b3IgagpAZW5kaWYKCkBpZihkaWFsZWN0PW15c3FsKQogIGJpbyBTCiAgYXZhdGFyIEIKQGVuZGlmCgpAaWYoZGlhbGVjdD1zcWxpdGUpCiAgYmlvIFMKICBhdmF0YXIgQgpAZW5kaWYKCiAgc3RhdHVzIHMxNiA9ICdhY3RpdmUn)

### Compile for Different Dialects

```bash
rune schema.ss -d pg    # includes bio, avatar, search_vector
rune schema.ss -d mysql # includes bio, avatar
rune schema.ss -d sqlite # includes bio, avatar
```

### Nested Conditionals

```ss
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
```

[▶ Open in Playground](../../playground/index.html#JCBhbmFseXRpY3MgdXRmOG1iNAoKQHZlcnNpb24gMi4xLjAKCiMgZXZlbnRzCiAgaWQgbisrCiAgdXNlcl9pZCBuID4gdXNlcnMuaWQKICBldmVudF90eXBlIHM2NAogIHBheWxvYWQgagogIGNyZWF0ZWRfYXQgdAoKQGlmKGRpYWxlY3Q9cGcpCiAgc2VhcmNoX3ZlYyBqCiAgZ2VvX3BvaW50IEkKQGVuZGlmCgpAaWYoZGlhbGVjdD1teXNxbHxzcWxpdGUpCiAgZ2VvX2xhdCBuCiAgZ2VvX2xuZyBuCkBlbmRpZgoKIyB1c2VycwogIGlkIG4rKwogIGVtYWlsIHMyNTVAdQogIG5hbWUgczEwMAoKJiByZWNlbnRfZXZlbnRzID0gU0VMRUNUIGUuKiwgdS5lbWFpbAogIEZST00gZXZlbnRzIGUKICBKT0lOIHVzZXJzIHUgT04gZS51c2VyX2lkID0gdS5pZAogIFdIRVJFIGUuY3JlYXRlZF9hdCA-IE5PVygpIC0gSU5URVJWQUwgNyBEQVkKCiYgZXZlbnRfdHlwZXMgPSBTRUxFQ1QgRElTVElOQ1QgZXZlbnRfdHlwZSBGUk9NIGV2ZW50cw)

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
