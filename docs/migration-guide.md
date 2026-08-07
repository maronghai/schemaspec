# Migration Guide

This guide helps you migrate from other database schema tools to Rune.

## From SQL DDL

SQL DDL is verbose and repetitive. Rune's `.ss` format is compact and readable.

### Example: Users Table

**SQL DDL:**
```sql
CREATE TABLE users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

**Rune `.ss`:**
```ss
# users
  id N++
  username s50 @u
  email s @u
  password_hash s255
  is_active b?
  created_at t
  updated_at t
```

### Symbol Reference

| Symbol | SQL Type | Description |
|--------|----------|-------------|
| `N` | BIGINT | 64-bit integer |
| `n` | INT | 32-bit integer |
| `s` | VARCHAR(255) | Short string |
| `s50` | VARCHAR(50) | Parameterized string |
| `b` | BOOLEAN | Boolean |
| `t` | DATETIME | DateTime |
| `++` | AUTO_INCREMENT PRIMARY KEY | Auto-increment PK |
| `!` | PRIMARY KEY | Primary key |
| `?` | NULLABLE | Nullable field (fields are NOT NULL by default) |
| `@u` | UNIQUE | Unique constraint |

### Migration Steps

1. **Export your SQL schema:**
   ```bash
   mysqldump --no-data your_database > schema.sql
   ```

2. **Reverse-engineer to `.ss`:**
   ```bash
   rune reverse schema.sql -t > schema.ss
   ```

3. **Review and clean up:**
   - Check template extraction results
   - Adjust field names and types as needed
   - Add comments for documentation

4. **Validate the new schema:**
   ```bash
   rune validate schema.ss -s
   ```

5. **Generate SQL to verify:**
   ```bash
   rune schema.ss -d mysql > schema_new.sql
   ```

## From Prisma

Prisma uses a TypeScript-like schema definition. Rune is more compact.

### Example: Users Table

**Prisma Schema:**
```prisma
model User {
  id        Int      @id @default(autoincrement()) @db.BigInt
  username  String   @unique @db.VarChar(50)
  email     String   @unique @db.VarChar(255)
  passwordHash String @map("password_hash") @db.VarChar(255)
  isActive  Boolean  @default(true) @map("is_active")
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("users")
}
```

**Rune `.ss`:**
```ss
# users
  id N++
  username s50 @u
  email s @u
  password_hash s255
  is_active b?
  created_at t
  updated_at t
```

### Migration Steps

1. **Export Prisma schema to SQL:**
   ```bash
   prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script > schema.sql
   ```

2. **Reverse-engineer to `.ss`:**
   ```bash
   rune reverse schema.sql -t > schema.ss
   ```

3. **Clean up:**
   - Remove Prisma-specific comments
   - Adjust field mappings
   - Verify types match your database

4. **Validate and generate:**
   ```bash
   rune validate schema.ss -s
   rune schema.ss -d pg > schema_new.sql
   ```

## From Knex

Knex migrations are JavaScript-based. Rune is declarative.

### Example: Users Table

**Knex Migration:**
```javascript
exports.up = function(knex) {
  return knex.schema.createTable('users', table => {
    table.increments('id').primary();
    table.string('username', 50).notNullable().unique();
    table.string('email', 255).notNullable().unique();
    table.string('password_hash', 255).notNullable();
    table.boolean('is_active').defaultTo(true);
    table.timestamps(true, true);
  });
};

exports.down = function(knex) {
  return knex.schema.dropTable('users');
};
```

**Rune `.ss`:**
```ss
# users
  id N++
  username s50 @u
  email s @u
  password_hash s255
  is_active b?
  created_at t
  updated_at t
```

### Migration Steps

1. **Export current schema:**
   ```bash
   # Run your migrations against a test database, then dump it
   pg_dump --schema-only your_database > schema.sql
   ```

2. **Reverse-engineer to `.ss`:**
   ```bash
   rune reverse schema.sql -t > schema.ss
   ```

3. **Clean up:**
   - Knex uses snake_case by default (good!)
   - Check auto-generated timestamps
   - Verify foreign key relationships

4. **Validate and generate:**
   ```bash
   rune validate schema.ss -s
   rune schema.ss -d pg > schema_new.sql
   ```

## Tips

### Start Small

Don't migrate your entire schema at once. Start with one or two tables:

1. Pick a simple table (like `users`)
2. Create the `.ss` version
3. Validate it generates the same SQL
4. Gradually expand to other tables

### Use Templates

Rune templates reduce repetition. Extract common patterns:

```
% audit
  created_at t
  updated_at t
  ...

# users
  id N++
  username s50 @u
  #audit

# posts
  id N++
  title s
  #audit
```

### Validate Often

Run validation after every change:

```bash
rune validate schema.ss -s
```

The `-s` flag shows statistics, helping you spot missing fields.

### Use Migration Mode

When migrating incrementally, use Rune's migration feature:

```bash
rune migrate old.ss new.ss --rollback > rollback.sql
```

This generates safe rollback SQL for your migration.

### Test with Multiple Dialects

If your application supports multiple databases, validate all targets:

```bash
rune schema.ss -d mysql > schema_mysql.sql
rune schema.ss -d pg > schema_pg.sql
rune schema.ss -d sqlite > schema_sqlite.sql
```

## Getting Help

- **Documentation:** [README.md](../README.md)
- **Examples:** See the `tests/` directory for real-world examples
- **Issues:** Open an issue on GitHub
