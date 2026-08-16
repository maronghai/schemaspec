# Lesson 7: Code Generators

**Duration**: 15 minutes

## Objective

Generate application code from `.ss` schemas — ORM models, API specs, validation schemas.

## Generator Registry

```
rune generate <generator> [input.ss] [options]
```

List all generators:
```bash
rune generate --list
```

| Generator | Output | Category | Dialects |
|-----------|--------|----------|----------|
| `json-schema` | `.json` | standalone | all (agnostic) |
| `sql-ddl` | `.sql` | schema | all 6 |
| `prisma` | `.prisma` | schema | all (agnostic) |
| `docs` | `.md` | schema | all (agnostic) |
| `drizzle` | `.ts` | schema | mysql, pg, sqlite |
| `typeorm` | `.ts` | schema | mysql, pg, sqlite, mssql |
| `sqlalchemy` | `.py` | schema | mysql, pg, sqlite |
| `knex` | `.js` | schema | mysql, pg, sqlite, mssql |
| `openapi` | `.json` | schema | mysql, pg, sqlite, mssql, oracle |
| `graphql` | `.graphql` | schema | all (agnostic) |
| `symbol-index` | `.json` | standalone | all 6 |
| `pydantic` | `.py` | schema | all (agnostic) |

## Single Generator

```bash
rune generate prisma schema.ss
rune generate drizzle schema.ss -d pg
rune generate openapi schema.ss -o api.json
```

## Batch Generation

```bash
rune generate schema.ss --generators prisma,drizzle,openapi
rune generate schema.ss --generators all -d pg
rune generate schema.ss --dry-run  # preview without writing
```

Output files: `schema.prisma`, `schema.ts`, `schema.json`, etc.

## Generator Examples

### Prisma

```bash
rune generate prisma blog.ss
```

```prisma
// blog.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  posts     Post[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

model Post {
  id        Int      @id @default(autoincrement())
  title     String
  body      String?
  status    String   @default("draft")
  author    User     @relation(fields: [authorId], references: [id])
  authorId  Int
  createdAt DateTime @default(now())
}
```

### Drizzle (TypeScript)

```bash
rune generate drizzle blog.ss -d pg
```

```typescript
// blog.ts
import { pgTable, serial, varchar, text, timestamp, pgEnum } from 'drizzle-orm/pg-core';

export const statusEnum = pgEnum('status', ['draft', 'published', 'archived']);

export const users = pgTable('users', {
  id: serial('id').primaryKey(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const posts = pgTable('posts', {
  id: serial('id').primaryKey(),
  title: varchar('title', { length: 200 }).notNull(),
  body: text('body'),
  status: statusEnum('status').default('draft').notNull(),
  authorId: serial('author_id').references(() => users.id).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
```

### OpenAPI 3.1

```bash
rune generate openapi blog.ss -o openapi.json
```

```json
{
  "openapi": "3.1.0",
  "components": {
    "schemas": {
      "User": {
        "type": "object",
        "properties": {
          "id": { "type": "integer", "format": "int64" },
          "email": { "type": "string", "format": "email", "maxLength": 255 },
          "name": { "type": "string", "maxLength": 100 },
          "createdAt": { "type": "string", "format": "date-time" }
        },
        "required": ["id", "email", "name"]
      }
    }
  }
}
```

### Pydantic v2

```bash
rune generate pydantic blog.ss
```

```python
# blog.py
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional

class User(BaseModel):
    id: int
    email: EmailStr
    name: str
    created_at: datetime

    model_config = {"from_attributes": True}

class Post(BaseModel):
    id: int
    title: str
    body: Optional[str] = None
    status: str = "draft"
    author_id: int
    created_at: datetime

    model_config = {"from_attributes": True}
```

## Dialect-Aware Generation

For dialect-specific generators (`drizzle`, `typeorm`, `sqlalchemy`, `knex`, `openapi`, `sql-ddl`):

```bash
rune generate drizzle schema.ss -d pg
rune generate sqlalchemy schema.ss -d mysql
rune generate openapi schema.ss -d pg -o api.json
```

Agnostic generators (`prisma`, `docs`, `graphql`, `json-schema`, `pydantic`, `symbol-index`) ignore `-d`.

## Documentation Generator

```bash
rune docs schema.ss -o docs.md
rune docs schema.ss --format json -o docs.json
```

Generates Markdown with table docs, field types, indexes, FKs, and Mermaid ER diagram.

## Exercise

Using `exercise4.ss` (blog schema):

```bash
# Generate all ORM models for PostgreSQL
rune generate exercise4.ss --generators prisma,drizzle,typeorm,sqlalchemy -d pg

# Generate API spec
rune generate exercise4.ss --generators openapi,graphql -d pg

# Generate documentation
rune docs exercise4.ss -o blog-docs.md

# Validate generated code compiles
cd generated && npx tsc --noEmit  # for TypeScript outputs
```

## Key Takeaways

- `rune generate <gen> schema.ss` — single generator
- `rune generate schema.ss --generators gen1,gen2` — batch mode
- `--dry-run` previews output without writing files
- Dialect-specific generators need `-d <dialect>`
- Agnostic generators: `prisma`, `docs`, `graphql`, `json-schema`, `pydantic`, `symbol-index`
- Output extensions: `.prisma`, `.ts`, `.py`, `.js`, `.json`, `.graphql`, `.md`
- `rune docs` generates Markdown with Mermaid ER diagram

---

**Next**: [Lesson 8: CI/CD Integration →](08-ci-integration.md)
