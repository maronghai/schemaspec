# Rune Interactive Tutorial

Welcome to the Rune tutorial! This hands-on guide will teach you how to design database schemas using Rune's minimal `.ss` syntax, compile them to SQL for any dialect, generate migrations, and integrate with your development workflow.

## Prerequisites

- Basic SQL knowledge (tables, columns, foreign keys, indexes)
- A terminal with `rune` installed (`brew install rune` / `scoop install rune` / `npx rune`)
- Optional: VS Code with the Rune extension for syntax highlighting and LSP support

## Lessons

| Lesson | Topic | Duration | Key Concepts |
|--------|-------|----------|--------------|
| [01](01-schema-basics.md) | **Schema Basics** | 10 min | `$` declaration, `#` tables, type symbols (`n`, `s`, `t`, `b`), modifiers (`++`, `!`, `?`) |
| [02](02-custom-types.md) | **Custom Types** | 10 min | `~` type aliases, dialect overrides, reusable `uuid`, `money`, `status` types |
| [03](03-templates.md) | **Templates & Inheritance** | 15 min | `%` templates, `...` slot marker, mixin inheritance (`+`), field injection order |
| [04](04-foreign-keys.md) | **Foreign Keys & Relationships** | 15 min | Inline `>` FKs, standalone `>` FKs, actions (`-C`, `-N`), autofk (`$ ... autofk`) |
| [05](05-indexes-constraints.md) | **Indexes & Constraints** | 15 min | `@` inline indexes, `@u` unique, standalone `@` indexes, composite PK (`!`), CHECK constraints (`[]`, `{}`) |
| [06](06-views-conditionals.md) | **Views & Conditional Schemas** | 15 min | `&` views, set operators, `@if(dialect=)` blocks, dialect-specific fields |
| [07](07-generators.md) | **Code Generators** | 15 min | `rune generate` — Prisma, Drizzle, TypeORM, SQLAlchemy, OpenAPI, GraphQL, Pydantic, JSON Schema |
| [08](08-ci-integration.md) | **CI/CD Integration** | 15 min | `rune validate`, `rune check`, `rune diff --check`, `rune migrate`, GitHub Actions, pre-commit hooks |

## Quick Start (TL;DR)

```bash
# 1. Create a starter schema
rune init myapp

# 2. Edit myapp.ss with your schema
# 3. Compile to SQL (MySQL default)
rune myapp.ss -o schema.sql

# 4. Compile for PostgreSQL
rune myapp.ss -d pg -o schema.pg.sql

# 5. Generate a migration from v1 to v2
rune migrate v1.ss v2.ss -o migration.sql

# 6. Reverse engineer existing SQL
rune reverse existing.sql -o recovered.ss

# 7. Generate ORM code
rune generate prisma myapp.ss
rune generate drizzle myapp.ss
rune generate typeorm myapp.ss

# 8. Validate in CI
rune check myapp.ss  # exit 1 on error
```

## Next Steps

Start with **[Lesson 1: Schema Basics](01-schema-basics.md)** →
