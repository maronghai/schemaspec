# Lesson 5: Indexes & Constraints

**Duration**: 15 minutes

## Objective

Learn inline indexes, standalone indexes, composite primary keys, and CHECK constraints.

## Inline Indexes

```
field_name type @[u]     # @ = regular, @u = unique
```

```ss
# users
  id n++
  email s255@u           # UNIQUE INDEX idx_email (email)
  name s100@             # INDEX idx_name (name)
  status s16
```

## Standalone Indexes

```
@ [u|f] [index_name] (field1, field2, ...)
```

| Prefix | Type |
|--------|------|
| (none) | Regular index |
| `u` | Unique index |
| `f` | Fulltext index |

```ss
# users
  id n++
  email s255
  first_name s50
  last_name s50
  status s16

@ email                          # idx_email (email)
@ u (email, status)             # idx_email_status (email, status) UNIQUE
@ f (first_name, last_name)     # idx_fulltext (fulltext)
@ idx_custom (last_name, first_name)  # named index
```

### Descending Order

```ss
@ idx_sort (created_at-, id-)   # DESC on both columns
```

## Composite Primary Key

```
! field1, field2, ...
```

```ss
# user_roles
  user_id n
  role_id n
  ! user_id, role_id      -- PRIMARY KEY (user_id, role_id)
```

> **Note**: Composite PK fields are implicitly `NOT NULL`.

## CHECK Constraints

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[a,b]` | BETWEEN a AND b (inclusive) | `age [0,150]` |
| `[a,b)` | a ≤ x < b | `score [0,100)` |
| `(a,b]` | a < x ≤ b | `ratio (0,1]` |
| `(a,b)` | a < x < b | `temp (-40,50)` |
| `{v1,v2}` | IN list | `status {'A','B','C'}` |
| `{>0}` | Comparison | `price {>0}` |

```ss
# products
  id n++
  price m {>0}
  qty n [0,10000]
  status s16 {'active','inactive','discontinued'}
  rating n [1,5]
```

## Generated Columns

```
field_name AS (expression) [VIRTUAL|STORED]
```

```ss
# orders
  id n++
  price m
  qty n
  total AS (price * qty) STORED
  tax AS (total * 0.1) VIRTUAL
```

## Exercise

Create `exercise5.ss`:
```ss
$ shop utf8mb4

# users
  id n++
  email s255@u
  first_name s50
  last_name s50
  age n [18,120]
  status s16 {'active','inactive','banned'}
  created_at t
  @ idx_name (last_name, first_name)
  @ u email

# products
  id n++
  sku s32@u
  name s200
  price m {>0}
  cost m {>0}
  margin AS (price - cost) VIRTUAL
  stock n [0,]
  status s16 {'active','discontinued','draft'}

# orders
  id n++
  user_id n > users.id -C
  status s16 {'pending','paid','shipped','cancelled','refunded'}
  subtotal m {>0}
  tax m {>=0}
  total AS (subtotal + tax) STORED
  created_at t
  @ (user_id, created_at)
  @ u (user_id, id)

# order_items
  order_id n > orders.id -C
  product_id n > products.id
  qty n [1,]
  unit_price m {>0}
  line_total AS (qty * unit_price) STORED
  ! order_id, product_id
```

Verify constraints in output:
```bash
rune exercise5.ss -d mysql | grep -E "(CHECK|INDEX|PRIMARY KEY|UNIQUE)"
rune exercise5.ss -d pg | grep -E "(CHECK|INDEX|PRIMARY KEY|UNIQUE)"
```

## Key Takeaways

- Inline: `@` (index), `@u` (unique) on field declaration
- Standalone: `@ [u|f] [name] (cols...)` — composite, named, fulltext
- Descending: `col-` suffix in index field list
- Composite PK: `! col1, col2, ...`
- CHECK: `[a,b]`, `[a,b)`, `(a,b]`, `(a,b)`, `{list}`, `{>0}`, `{<100}`
- Generated columns: `field AS (expr) [VIRTUAL|STORED]`
- All compile to dialect-appropriate SQL

---

**Next**: [Lesson 6: Views & Conditional Schemas →](06-views-conditionals.md)
