# Lesson 3: Templates & Inheritance

**Duration**: 15 minutes

## Objective

Master templates (`%`) — reusable field sets with inheritance and slot-based composition.

## The Problem

Repeating common fields across tables (timestamps, soft-delete, audit trail) is error-prone.

```ss
# users
  id n++
  name s100
  created_at t
  updated_at t
  deleted_at t?

# posts
  id n++
  title s200
  created_at t
  updated_at t
  deleted_at t?
```

## Template Declaration

```
% template_name [> parent1 + parent2]
  field declarations...
  ...
```

```ss
% timestamps
  created_at t
  updated_at t
  ...
```

The `...` (slot marker) controls where **child fields** are injected.

## Applying Templates to Tables

```
# [template_ref] table_name
```

```ss
% timestamps
  created_at t
  updated_at t
  ...

# timestamps users
  id n++
  name s100

# timestamps posts
  id n++
  title s200
```

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
% audit
  created_by n
  created_at t
  ...
  updated_by n
  updated_at t

% soft_delete
  deleted_at t?
  deleted_by n?
  ...

# audit + soft_delete users
  id n++
  name s100
```

**Result order**: `created_by`, `created_at`, `id`, `name`, `deleted_at`, `deleted_by`, `updated_by`, `updated_at`

## Template Inheritance (Mixin)

```
% child_template > parent1 + parent2
  child_field n
  ...
```

Max 4 parents via `+` syntax.

```ss
% base
  id n++
  ...

% timestamps
  created_at t
  updated_at t
  ...

% soft_delete
  deleted_at t?
  ...

% full_audit > base + timestamps + soft_delete
  created_by n
  updated_by n
  ...

# full_audit users
  name s100
  email s@u
```

## Template Type Conflicts

If parent and child define the same field name with different types, the **child wins** and a warning is emitted.

```ss
% base
  id n++
  ...

% derived > base
  id s++      # WARNING: type conflict (n vs s), child 's' wins
  name s100
```

## Template Without Slot (`...`)

If a template has no `...`, its fields are **prepended** to the child table.

```ss
% prefix_only
  tenant_id n
  shard_id n

# prefix_only users
  id n++
  name s100
```

Result: `tenant_id`, `shard_id`, `id`, `name`

## Exercise

Create `exercise3.ss`:
```ss
$ saas utf8mb4

% timestamps
  created_at t
  updated_at t
  ...

% soft_delete
  deleted_at t?
  deleted_by n?
  ...

% audit > timestamps
  created_by n
  updated_by n
  ...

% base
  id n++
  ...

% entity > base + audit + soft_delete
  ...

# entity users
  email s255@u
  name s100
  status e('active','inactive','suspended') = 'active'

# entity organizations
  name s100
  slug s64@u
  plan e('free','pro','enterprise') = 'free'
```

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
