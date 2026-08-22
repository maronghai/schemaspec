# Lesson 4: Foreign Keys & Relationships

**Duration**: 15 minutes

## Objective

Master foreign key declaration — inline, standalone, actions, and autofk.

## Inline Foreign Keys

```
field_name type > ref_table[.ref_field] [actions]
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyB1c2VycwogIGlkIG4rKwogIG5hbWUgczEwMAoKIyBwb3N0cwogIGlkIG4rKwogIHVzZXJfaWQgbiA-IHVzZXJzLmlkCiAgdGl0bGUgczIwMA)

**Shorthands**:
```ss
```

[▶ Open in Playground](../../playground/index.html#dXNlcl9pZCBuID4gdXNlcnMuICAgICAjIHJlZl9maWVsZCBpbmZlcnJlZCBmcm9tIGxvY2FsIG5hbWUgKHVzZXJfaWQg4oaSIGlkKQo-IHVzZXJzICAgICAgICAgICAgICAgICMgdWx0cmEtc2hvcnQ6IGxvY2FsPXVzZXJfaWQsIHJlZj11c2Vycy5pZApjYXRlZ29yeV9pZCA-IGNhdGVnb3JpZXM)

## FK Actions

| Suffix | ON DELETE | ON UPDATE |
|--------|-----------|-----------|
| `-C` | CASCADE | — |
| `-N` | SET NULL | — |
| `C` | — | CASCADE |
| `N` | — | SET NULL |

```ss
```

[▶ Open in Playground](../../playground/index.html#IyBvcmRlcnMKICBpZCBuKysKICB1c2VyX2lkIG4gPiB1c2Vycy5pZCAtQyAgICAgICMgT04gREVMRVRFIENBU0NBREUKICBhZGRyZXNzX2lkIG4gPiBhZGRyZXNzZXMuaWQgLU4gQyAgIyBPTiBERUxFVEUgU0VUIE5VTEwsIE9OIFVQREFURSBDQVNDQURF)

## Standalone Foreign Keys

```
> local_field ref_table[.ref_field] [actions]
```

```ss
```

[▶ Open in Playground](../../playground/index.html#IyBwb3N0cwogIGlkIG4rKwogIHVzZXJfaWQgbgogIHRpdGxlIHMyMDAKICA-IHVzZXJfaWQgdXNlcnMuaWQgLUM)

Use when:
- Field already declared without FK
- Composite FK (multiple columns)
- Separation of concerns

## Composite Foreign Keys

```ss
```

[▶ Open in Playground](../../playground/index.html#IyBvcmRlcl9pdGVtcwogIG9yZGVyX2lkIG4gPiBvcmRlcnMuaWQKICBwcm9kdWN0X2lkIG4gPiBwcm9kdWN0cy5pZAogIHF0eSBuCiAgPiAob3JkZXJfaWQsIHByb2R1Y3RfaWQpIG9yZGVyc19wcm9kdWN0cw)

> **Note**: Composite FK syntax uses `> (col1, col2) ref_table`

## Autofk — Automatic FK Inference

Enable in schema declaration:
```ss
```

[▶ Open in Playground](../../playground/index.html#JCBteWFwcCB1dGY4bWI0IGF1dG9maw)

Any field ending in `_id` (configurable) automatically gets an FK to the singular table:
```ss
```

[▶ Open in Playground](../../playground/index.html#IyBwb3N0cwogIGlkIG4rKwogIHVzZXJfaWQgbiAgICAgICAgIyDihpIgRksgdG8gdXNlcnMuaWQKICBjYXRlZ29yeV9pZCBuICAgICMg4oaSIEZLIHRvIGNhdGVnb3JpZXMuaWQ)

Disable per-field with `!`:
```ss
```

[▶ Open in Playground](../../playground/index.html#dXNlcl9pZCBuISAgICAgICAgICMgbm8gYXV0b2ZrLCBleHBsaWNpdCBQSyBpbnN0ZWFk)

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
```

[▶ Open in Playground](../../playground/index.html#JCBibG9nIHV0ZjhtYjQgYXV0b2ZrCgojIHVzZXJzCiAgaWQgbisrCiAgZW1haWwgczI1NUB1CiAgbmFtZSBzMTAwCgojIGNhdGVnb3JpZXMKICBpZCBuKysKICBuYW1lIHM2NEB1CiAgc2x1ZyBzNjRAdQoKIyBwb3N0cwogIGlkIG4rKwogIHVzZXJfaWQgbgogIGNhdGVnb3J5X2lkIG4KICB0aXRsZSBzMjAwCiAgYm9keSBTCiAgc3RhdHVzIGUoJ2RyYWZ0JywncHVibGlzaGVkJywnYXJjaGl2ZWQnKSA9ICdkcmFmdCcKICBwdWJsaXNoZWRfYXQgdD8KICA-IHVzZXJfaWQgdXNlcnMuaWQgLUMKICA-IGNhdGVnb3J5X2lkIGNhdGVnb3JpZXMuaWQgLU4KCiMgY29tbWVudHMKICBpZCBuKysKICBwb3N0X2lkIG4gPiBwb3N0cy5pZCAtQwogIHVzZXJfaWQgbiA-IHVzZXJzLmlkIC1DCiAgYm9keSBzMTAwMAogIGNyZWF0ZWRfYXQgdA)

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
