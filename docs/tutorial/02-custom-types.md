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
```

## Dialect Overrides

```ss
```

Use the target dialect's native type syntax. Rune passes these through directly.

## Using Custom Types

```ss
```

[▶ Open in Playground](../../playground/index.html#JCBzaG9wCgp-IHV1aWQgbiBteXNxbD1jaGFyKDM2KSBwZz11dWlkCn4gbW9uZXkgbQp-IHNrdSBzMzIKCiMgcHJvZHVjdHMKICBpZCB1dWlkKysKICBjb2RlIHNrdUB1CiAgcHJpY2UgbW9uZXkKICBuYW1lIHMyMDA)

Compile for different dialects:
```bash
rune shop.ss -d mysql  # id char(36), price decimal(16,2)
rune shop.ss -d pg     # id uuid, price numeric(16,2)
```

## Custom Types Referencing Custom Types

```ss
```

[▶ Open in Playground](../../playground/index.html#fiB1dWlkIG4gbXlzcWw9Y2hhcigzNikgcGc9dXVpZAp-IHVzZXJfaWQgdXVpZCAgICAgICAgICAjIHJlZmVyZW5jZXMgfnV1aWQKfiBvcmRlcl9pZCB1dWlk)

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
```

[▶ Open in Playground](../../playground/index.html#JCBzaG9wIHV0ZjhtYjQKCn4gdXVpZCBuIG15c3FsPWNoYXIoMzYpIHBnPXV1aWQKfiBtb25leSBtCn4gc2t1IHMzMgoKIyBwcm9kdWN0cwogIGlkIHV1aWQrKwogIGNvZGUgc2t1QHUKICBwcmljZSBtb25leQogIG5hbWUgczIwMAogIGRlc2NyaXB0aW9uIFM_CiAgYWN0aXZlIGIgPSB0cnVlCiAgY3JlYXRlZF9hdCB0)

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
