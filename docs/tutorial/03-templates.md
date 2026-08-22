# Lesson 3: Templates & Inheritance

**Duration**: 15 minutes

## Objective

Master templates (`%`) — reusable field sets with inheritance and slot-based composition.

## The Problem

Repeating common fields across tables (timestamps, soft-delete, audit trail) is error-prone.

```ss
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMAogIGNyZWF0ZWRfYXQgdAogIHVwZGF0ZWRfYXQgdAogIGRlbGV0ZWRfYXQgdD8KCiMgcG9zdHMKICBpZCBuKysKICB0aXRsZSBzMjAwCiAgY3JlYXRlZF9hdCB0CiAgdXBkYXRlZF9hdCB0CiAgZGVsZXRlZF9hdCB0Pw)

## Template Declaration

```
% template_name [> parent1 + parent2]
  field declarations...
  ...
```

```ss
```

The `...` (slot marker) controls where **child fields** are injected.

## Applying Templates to Tables

```
# [template_ref] table_name
```

```ss
```

[▶ Open in Playground](../../playground/index.html#JSB0aW1lc3RhbXBzCiAgY3JlYXRlZF9hdCB0CiAgdXBkYXRlZF9hdCB0CiAgLi4uCgojIHRpbWVzdGFtcHMgdXNlcnMKICBpZCBuKysKICBuYW1lIHMxMDAKCiMgdGltZXN0YW1wcyBwb3N0cwogIGlkIG4rKwogIHRpdGxlIHMyMDA)

### Compiled Output

```sql
-- users
created_at datetime NOT NULL,
updated_at datetime NOT NULL,
id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
name varchar(100) NOT NULL

-- posts
created_at datetime NOT NULL,
updated_at datetime NOT NULL,
id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
title varchar(200) NOT NULL
```

**Fields before `...` in template → child fields → fields after `...` in template**

## Slot Mechanics

```
% template
  a n
  ...
  b n

# template table
  x n
  y n
```

**Merge order**: `a` (parent before) → `x, y` (child) → `b` (parent after)

```ss
```

[▶ Open in Playground](../../playground/index.html#JSBhdWRpdAogIGNyZWF0ZWRfYnkgbgogIGNyZWF0ZWRfYXQgdAogIC4uLgogIHVwZGF0ZWRfYnkgbgogIHVwZGF0ZWRfYXQgdAoKJSBzb2Z0X2RlbGV0ZQogIGRlbGV0ZWRfYXQgdD8KICBkZWxldGVkX2J5IG4_CiAgLi4uCgojIGF1ZGl0ICsgc29mdF9kZWxldGUgdXNlcnMKICBpZCBuKysKICBuYW1lIHMxMDA)

**Result order**: `created_by`, `created_at`, `id`, `name`, `deleted_at`, `deleted_by`, `updated_by`, `updated_at`

## Template Inheritance (Mixin)

```
% child_template > parent1 + parent2
  child_field n
  ...
```

Max 4 parents via `+` syntax.

```ss
```

[▶ Open in Playground](../../playground/index.html#JSBiYXNlCiAgaWQgbisrCiAgLi4uCgolIHRpbWVzdGFtcHMKICBjcmVhdGVkX2F0IHQKICB1cGRhdGVkX2F0IHQKICAuLi4KCiUgc29mdF9kZWxldGUKICBkZWxldGVkX2F0IHQ_CiAgLi4uCgolIGZ1bGxfYXVkaXQgPiBiYXNlICsgdGltZXN0YW1wcyArIHNvZnRfZGVsZXRlCiAgY3JlYXRlZF9ieSBuCiAgdXBkYXRlZF9ieSBuCiAgLi4uCgojIGZ1bGxfYXVkaXQgdXNlcnMKICBuYW1lIHMxMDAKICBlbWFpbCBzQHU)

## Template Type Conflicts

If parent and child define the same field name with different types, the **child wins** and a warning is emitted.

```ss
```

[▶ Open in Playground](../../playground/index.html#JSBiYXNlCiAgaWQgbisrCiAgLi4uCgolIGRlcml2ZWQgPiBiYXNlCiAgaWQgcysrICAgICAgIyBXQVJOSU5HOiB0eXBlIGNvbmZsaWN0IChuIHZzIHMpLCBjaGlsZCAncycgd2lucwogIG5hbWUgczEwMA)

## Template Without Slot (`...`)

If a template has no `...`, its fields are **prepended** to the child table.

```ss
```

[▶ Open in Playground](../../playground/index.html#JSBwcmVmaXhfb25seQogIHRlbmFudF9pZCBuCiAgc2hhcmRfaWQgbgoKIyBwcmVmaXhfb25seSB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMA)

Result: `tenant_id`, `shard_id`, `id`, `name`

## Exercise

Create `exercise3.ss`:
```ss
```

[▶ Open in Playground](../../playground/index.html#JCBzYWFzIHV0ZjhtYjQKCiUgdGltZXN0YW1wcwogIGNyZWF0ZWRfYXQgdAogIHVwZGF0ZWRfYXQgdAogIC4uLgoKJSBzb2Z0X2RlbGV0ZQogIGRlbGV0ZWRfYXQgdD8KICBkZWxldGVkX2J5IG4_CiAgLi4uCgolIGF1ZGl0ID4gdGltZXN0YW1wcwogIGNyZWF0ZWRfYnkgbgogIHVwZGF0ZWRfYnkgbgogIC4uLgoKJSBiYXNlCiAgaWQgbisrCiAgLi4uCgolIGVudGl0eSA-IGJhc2UgKyBhdWRpdCArIHNvZnRfZGVsZXRlCiAgLi4uCgojIGVudGl0eSB1c2VycwogIGVtYWlsIHMyNTVAdQogIG5hbWUgczEwMAogIHN0YXR1cyBlKCdhY3RpdmUnLCdpbmFjdGl2ZScsJ3N1c3BlbmRlZCcpID0gJ2FjdGl2ZScKCiMgZW50aXR5IG9yZ2FuaXphdGlvbnMKICBuYW1lIHMxMDAKICBzbHVnIHM2NEB1CiAgcGxhbiBlKCdmcmVlJywncHJvJywnZW50ZXJwcmlzZScpID0gJ2ZyZWUn)

Compile and verify field order:
```bash
rune exercise3.ss -d pg
```

## Key Takeaways

- `%` declares templates; `# template table` applies them
- `...` slot controls injection point (parent before → child → parent after)
- Mixin inheritance: `% child > parent1 + parent2` (max 4 parents)
- Child fields override parent fields with same name (warning emitted)
- Templates compose: `audit > timestamps` → `entity > base + audit + soft_delete`
- Use for: timestamps, soft-delete, audit trail, multi-tenant, versioning

---

**Next**: [Lesson 4: Foreign Keys & Relationships →](04-foreign-keys.md)
