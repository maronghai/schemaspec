# Lesson 2: Custom Types

**Duration**: 10 minutes

## Objective

Learn to define reusable type aliases with `~` for consistency and dialect-specific overrides.

## Why Custom Types?

- **Consistency**: `~uuid` ensures all UUID columns use the same definition
- **Dialect overrides**: Map to native UUID in PostgreSQL, `char(36)` in MySQL
- **Semantic clarity**: `~money` is more expressive than `m`
- **Single source of truth**: Change in one place, propagates everywhere

## Syntax

```
~ type_name base_type [dialect=type ...]
```

## Basic Examples

```ss
~ uuid n
~ money m
~ email s256
~ status e('active','inactive','pending')
~ slug s64
```

## Dialect Overrides

```ss
~ uuid n mysql=char(36) pg=uuid sqlite=TEXT mssql=UNIQUEIDENTIFIER oracle=RAW(16) db2=CHAR(16) FOR BIT DATA
~ id n mysql=int pg=serial sqlite=INTEGER mssql=INT oracle=NUMBER(10) db2=INTEGER
```

Use the target dialect's native type syntax. Rune passes these through directly.

## Using Custom Types

```ss
$ shop

~ uuid n mysql=char(36) pg=uuid
~ money m
~ sku s32

# products
  id uuid++
  code sku@u
  price money
  name s200
```

Compile for different dialects:
```bash
rune shop.ss -d mysql  # id char(36), price decimal(16,2)
rune shop.ss -d pg     # id uuid, price numeric(16,2)
```

## Custom Types Referencing Custom Types

```ss
~ uuid n mysql=char(36) pg=uuid
~ user_id uuid          # references ~uuid
~ order_id uuid
```

Max reference depth: 32 (prevents infinite recursion).

## Resolution Order

1. Single-char symbols (`n`, `N`, `s`, etc.) → dialect symbol table
2. Parameterized (`s128`, `16,2`) → parsed as parameterized type
3. Unknown identifier → custom type lookup
4. Custom type → resolve its base type (recursive, max 32)
5. Dialect override → takes precedence over base type for that dialect

## Exercise

Extend `exercise1.ss` with custom types:
```ss
$ shop utf8mb4

~ uuid n mysql=char(36) pg=uuid
~ money m
~ sku s32

# products
  id uuid++
  code sku@u
  price money
  name s200
  description S?
  active b = true
  created_at t
```

Verify both dialects produce native UUID types:
```bash
rune exercise2.ss -d mysql | grep -A1 "id "
rune exercise2.ss -d pg | grep -A1 "id "
```

## Key Takeaways

- `~` defines reusable type aliases at schema level
- Dialect overrides use `dialect=type` syntax (space-separated)
- Custom types can chain (max depth 32)
- Overrides apply per-dialect at compile time
- Use for semantic types: `~email`, `~slug`, `~uuid`, `~money`, `~status`

---

**Next**: [Lesson 3: Templates & Inheritance →](03-templates.md)
