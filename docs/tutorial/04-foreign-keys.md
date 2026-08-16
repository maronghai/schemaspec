# Lesson 4: Foreign Keys & Relationships

**Duration**: 15 minutes

## Objective

Master foreign key declaration — inline, standalone, actions, and autofk.

## Inline Foreign Keys

```
field_name type > ref_table[.ref_field] [actions]
```

```ss
# users
  id n++
  name s100

# posts
  id n++
  user_id n > users.id
  title s200
```

**Shorthands**:
```ss
user_id n > users.     # ref_field inferred from local name (user_id → id)
> users                # ultra-short: local=user_id, ref=users.id
category_id > categories
```

## FK Actions

| Suffix | ON DELETE | ON UPDATE |
|--------|-----------|-----------|
| `-C` | CASCADE | — |
| `-N` | SET NULL | — |
| `C` | — | CASCADE |
| `N` | — | SET NULL |

```ss
# orders
  id n++
  user_id n > users.id -C      # ON DELETE CASCADE
  address_id n > addresses.id -N C  # ON DELETE SET NULL, ON UPDATE CASCADE
```

## Standalone Foreign Keys

```
> local_field ref_table[.ref_field] [actions]
```

```ss
# posts
  id n++
  user_id n
  title s200
  > user_id users.id -C
```

Use when:
- Field already declared without FK
- Composite FK (multiple columns)
- Separation of concerns

## Composite Foreign Keys

```ss
# order_items
  order_id n > orders.id
  product_id n > products.id
  qty n
  > (order_id, product_id) orders_products
```

> **Note**: Composite FK syntax uses `> (col1, col2) ref_table`

## Autofk — Automatic FK Inference

Enable in schema declaration:
```ss
$ myapp utf8mb4 autofk
```

Any field ending in `_id` (configurable) automatically gets an FK to the singular table:
```ss
# posts
  id n++
  user_id n        # → FK to users.id
  category_id n    # → FK to categories.id
```

Disable per-field with `!`:
```ss
user_id n!         # no autofk, explicit PK instead
```

## Referential Integrity Validation

Rune validates:
- Referenced table exists
- Referenced column exists (or is PK)
- Referenced column is unique (PK or UNIQUE)
- No circular FK dependencies (unless explicitly allowed)

```bash
rune validate schema.ss
```

## Exercise

Create `exercise4.ss`:
```ss
$ blog utf8mb4 autofk

# users
  id n++
  email s255@u
  name s100

# categories
  id n++
  name s64@u
  slug s64@u

# posts
  id n++
  user_id n
  category_id n
  title s200
  body S
  status e('draft','published','archived') = 'draft'
  published_at t?
  > user_id users.id -C
  > category_id categories.id -N

# comments
  id n++
  post_id n > posts.id -C
  user_id n > users.id -C
  body s1000
  created_at t
```

Compile and inspect FKs:
```bash
rune exercise4.ss -d mysql | grep -i "foreign key"
rune exercise4.ss -d pg | grep -i "foreign key"
```

## Key Takeaways

- Inline FK: `field type > ref_table.ref_field [actions]`
- Shorthands: `> users.`, `> users`
- Actions: `-C` (CASCADE), `-N` (SET NULL), `C`, `N` for UPDATE
- Standalone: `> local_field ref_table[.ref_field] [actions]`
- Composite FK: `> (col1, col2) ref_table`
- `autofk` enables `_id` → table.id inference
- Validation catches broken references at compile time

---

**Next**: [Lesson 5: Indexes & Constraints →](05-indexes-constraints.md)
