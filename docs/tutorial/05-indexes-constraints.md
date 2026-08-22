# Lesson 5: Indexes & Constraints

**Duration**: 15 minutes

## Objective

Learn inline indexes, standalone indexes, composite primary keys, and CHECK constraints.

## Inline Indexes

```
field_name type @[u]     # @ = regular, @u = unique
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIGVtYWlsIHMyNTVAdSAgICAgICAgICAgIyBVTklRVUUgSU5ERVggaWR4X2VtYWlsIChlbWFpbCkKICBuYW1lIHMxMDBAICAgICAgICAgICAgICMgSU5ERVggaWR4X25hbWUgKG5hbWUpCiAgc3RhdHVzIHMxNg)

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
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIGVtYWlsIHMyNTUKICBmaXJzdF9uYW1lIHM1MAogIGxhc3RfbmFtZSBzNTAKICBzdGF0dXMgczE2CgpAIGVtYWlsICAgICAgICAgICAgICAgICAgICAgICAgICAjIGlkeF9lbWFpbCAoZW1haWwpCkAgdSAoZW1haWwsIHN0YXR1cykgICAgICAgICAgICAgIyBpZHhfZW1haWxfc3RhdHVzIChlbWFpbCwgc3RhdHVzKSBVTklRVUUKQCBmIChmaXJzdF9uYW1lLCBsYXN0X25hbWUpICAgICAjIGlkeF9mdWxsdGV4dCAoZnVsbHRleHQpCkAgaWR4X2N1c3RvbSAobGFzdF9uYW1lLCBmaXJzdF9uYW1lKSAgIyBuYW1lZCBpbmRleA)

### Descending Order

```ss
```

[▶ Open in Playground](../../playground/index.html#QCBpZHhfc29ydCAoY3JlYXRlZF9hdC0sIGlkLSkgICAjIERFU0Mgb24gYm90aCBjb2x1bW5z)

## Composite Primary Key

```
! field1, field2, ...
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VyX3JvbGVzCiAgdXNlcl9pZCBuCiAgcm9sZV9pZCBuCiAgISB1c2VyX2lkLCByb2xlX2lkICAgICAgLS0gUFJJTUFSWSBLRVkgKHVzZXJfaWQsIHJvbGVfaWQp)

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
```

[▶ Open in Playground](../../playground/index.html#IyBwcm9kdWN0cwogIGlkIG4rKwogIHByaWNlIG0gez4wfQogIHF0eSBuIFswLDEwMDAwXQogIHN0YXR1cyBzMTYgeydhY3RpdmUnLCdpbmFjdGl2ZScsJ2Rpc2NvbnRpbnVlZCd9CiAgcmF0aW5nIG4gWzEsNV0)

## Generated Columns

```
field_name AS (expression) [VIRTUAL|STORED]
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyBvcmRlcnMKICBpZCBuKysKICBwcmljZSBtCiAgcXR5IG4KICB0b3RhbCBBUyAocHJpY2UgKiBxdHkpIFNUT1JFRAogIHRheCBBUyAodG90YWwgKiAwLjEpIFZJUlRVQUw)

## Exercise

Create `exercise5.ss`:
```ss
```

[▶ Open in Playground](../../playground/index.html#JCBzaG9wIHV0ZjhtYjQKCiMgdXNlcnMKICBpZCBuKysKICBlbWFpbCBzMjU1QHUKICBmaXJzdF9uYW1lIHM1MAogIGxhc3RfbmFtZSBzNTAKICBhZ2UgbiBbMTgsMTIwXQogIHN0YXR1cyBzMTYgeydhY3RpdmUnLCdpbmFjdGl2ZScsJ2Jhbm5lZCd9CiAgY3JlYXRlZF9hdCB0CiAgQCBpZHhfbmFtZSAobGFzdF9uYW1lLCBmaXJzdF9uYW1lKQogIEAgdSBlbWFpbAoKIyBwcm9kdWN0cwogIGlkIG4rKwogIHNrdSBzMzJAdQogIG5hbWUgczIwMAogIHByaWNlIG0gez4wfQogIGNvc3QgbSB7PjB9CiAgbWFyZ2luIEFTIChwcmljZSAtIGNvc3QpIFZJUlRVQUwKICBzdG9jayBuIFswLF0KICBzdGF0dXMgczE2IHsnYWN0aXZlJywnZGlzY29udGludWVkJywnZHJhZnQnfQoKIyBvcmRlcnMKICBpZCBuKysKICB1c2VyX2lkIG4gPiB1c2Vycy5pZCAtQwogIHN0YXR1cyBzMTYgeydwZW5kaW5nJywncGFpZCcsJ3NoaXBwZWQnLCdjYW5jZWxsZWQnLCdyZWZ1bmRlZCd9CiAgc3VidG90YWwgbSB7PjB9CiAgdGF4IG0gez49MH0KICB0b3RhbCBBUyAoc3VidG90YWwgKyB0YXgpIFNUT1JFRAogIGNyZWF0ZWRfYXQgdAogIEAgKHVzZXJfaWQsIGNyZWF0ZWRfYXQpCiAgQCB1ICh1c2VyX2lkLCBpZCkKCiMgb3JkZXJfaXRlbXMKICBvcmRlcl9pZCBuID4gb3JkZXJzLmlkIC1DCiAgcHJvZHVjdF9pZCBuID4gcHJvZHVjdHMuaWQKICBxdHkgbiBbMSxdCiAgdW5pdF9wcmljZSBtIHs-MH0KICBsaW5lX3RvdGFsIEFTIChxdHkgKiB1bml0X3ByaWNlKSBTVE9SRUQKICAhIG9yZGVyX2lkLCBwcm9kdWN0X2lk)

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
