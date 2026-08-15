# Rune Generator & Dialect Coverage Matrix

> **Single source of truth** for which `rune generate` generators support which SQL dialects.
> Derived directly from the `REGISTRY` in `rune/src/generator.zig` (12 generators, 6 dialects:
> `mysql`, `pg`, `sqlite`, `mssql`, `oracle`, `db2`). If this table disagrees with the code, the
> code is authoritative — regenerate from `generator.zig`.

## Generators

| Generator    | Output ext | Category   | Dialects supported                              |
|--------------|-----------|------------|-------------------------------------------------|
| `json-schema`  | `.json`   | standalone | **all** (dialect-agnostic)                      |
| `sql-ddl`      | `.sql`    | schema     | mysql, pg, sqlite, mssql, oracle, db2           |
| `prisma`       | `.prisma` | schema     | **all** (dialect-agnostic)                      |
| `docs`         | `.md`     | schema     | **all** (dialect-agnostic)                      |
| `drizzle`      | `.ts`     | schema     | mysql, pg, sqlite                               |
| `typeorm`      | `.ts`     | schema     | mysql, pg, sqlite, mssql                        |
| `sqlalchemy`   | `.py`     | schema     | mysql, pg, sqlite                               |
| `knex`         | `.js`     | schema     | mysql, pg, sqlite, mssql                        |
| `openapi`      | `.json`   | schema     | mysql, pg, sqlite, mssql, oracle                |
| `graphql`      | `.graphql`| schema     | **all** (dialect-agnostic)                      |
| `symbol-index` | `.json`   | standalone | mysql, pg, sqlite, mssql, oracle, db2           |
| `pydantic`     | `.py`     | schema     | **all** (dialect-agnostic)                      |

- **Agnostic generators** (5): `json-schema`, `prisma`, `docs`, `graphql`, `pydantic` — produce the
  same output regardless of dialect.
- **Dialect-specific generators** (7): `sql-ddl`, `drizzle`, `typeorm`, `sqlalchemy`, `knex`,
  `openapi`, `symbol-index` — emit dialect-aware output.

## Coverage by dialect

`X` = generator emits dialect-specific output for this dialect; `·` = generator is
dialect-agnostic (covers every dialect); blank = not supported.

| Generator    | mysql | pg  | sqlite | mssql | oracle | db2 |
|--------------|:-----:|:---:|:------:|:-----:|:------:|:---:|
| `json-schema`  |  ·  |  ·  |   ·    |  ·    |   ·    |  ·  |
| `sql-ddl`      |  X  |  X  |   X    |  X    |   X    |  X  |
| `prisma`       |  ·  |  ·  |   ·    |  ·    |   ·    |  ·  |
| `docs`         |  ·  |  ·  |   ·    |  ·    |   ·    |  ·  |
| `drizzle`      |  X  |  X  |   X    |       |        |     |
| `typeorm`      |  X  |  X  |   X    |  X    |        |     |
| `sqlalchemy`   |  X  |  X  |   X    |       |        |     |
| `knex`         |  X  |  X  |   X    |  X    |        |     |
| `openapi`      |  X  |  X  |   X    |  X    |   X    |     |
| `graphql`      |  ·  |  ·  |   ·    |  ·    |   ·    |  ·  |
| `symbol-index` |  X  |  X  |   X    |  X    |   X    |  X  |
| `pydantic`     |  ·  |  ·  |   ·    |  ·    |   ·    |  ·  |

### Per-dialect generator counts

| Dialect | Dialect-specific | + Agnostic (5) | Total |
|---------|:----------------:|:-------------:|:-----:|
| mysql   | 7 | 5 | 12 |
| pg      | 7 | 5 | 12 |
| sqlite  | 7 | 5 | 12 |
| mssql   | 5 | 5 | 10 |
| oracle  | 3 | 5 | 8  |
| db2     | 2 | 5 | 7  |

Every dialect is therefore reachable by `sql-ddl` (all 6) plus the 5 agnostic generators, so all
six dialects have full schema-generation coverage; `oracle` and `db2` additionally have the
fewest dialect-specific ORM/API generators.

## Notes

- Adding a generator = create `rune/src/generators/<name>.zig` + add one `REGISTRY` entry in
  `generator.zig`. The CLI picks it up automatically; update this matrix from the `REGISTRY`.
- `dialects = null` in a `REGISTRY` entry means dialect-agnostic (the `·` rows above).
- A comptime architecture-health test guarantees no two `REGISTRY` entries share a `name`.
