# Rune Schema Cookbook

Common database schema patterns implemented in Rune `.ss` format.

---

## Multi-Tenant Schema

A schema where each table has a `tenant_id` column for data isolation.

```ss
#base base_fields
  tenant_id  N       # Tenant identifier (required)
  created_at d       # Creation timestamp
  updated_at d       # Last update timestamp
  deleted_at d?      # Soft delete timestamp (nullable)

#base audit_fields
  created_by s255    # User who created the record
  updated_by s255    # User who last updated the record

#users table
  #base base_fields
  #base audit_fields
  email      s255!u  # Unique email
  name       s255    # Display name
  role       s50     # User role (admin, editor, viewer)

#posts table
  #base base_fields
  #base audit_fields
  title      s255    # Post title
  body       S       # Post content (unlimited text)
  author_id  i       # FK → users.id
  status     s20     # draft, published, archived

  FK author_id → users(id)

#categories table
  #base base_fields
  name       s100    # Category name
  slug       s100!u  # URL-friendly slug
```

### Key Patterns

- **`tenant_id N`** — Every table includes tenant identifier for Row-Level Security
- **`deleted_at d?`** — Nullable timestamp enables soft delete
- **`#base` template** — Shared fields extracted into reusable templates
- **`!u` modifier** — Unique constraint for natural keys (email, slug)

---

## Soft Delete Pattern

Tables support logical deletion without removing data.

```ss
#base soft_delete
  is_deleted  n!     # Boolean flag (0=active, 1=deleted)
  deleted_at  d?     # When the record was deleted
  deleted_by  s255?  # Who deleted the record

#users table
  #base soft_delete
  email     s255!u
  name      s255

#posts table
  #base soft_delete
  title     s255
  body      S
  author_id i

  FK author_id → users(id)
```

### Query Pattern

```sql
-- Active records only
SELECT * FROM users WHERE is_deleted = 0;

-- Recently deleted (recoverable)
SELECT * FROM users WHERE is_deleted = 1 AND deleted_at > DATE_SUB(NOW(), INTERVAL 30 DAY);
```

---

## Audit Trail Pattern

Track all changes to sensitive data with full history.

```ss
#users table
  email    s255!u
  name     s255
  created_at d
  updated_at d

#audit_log table
  id         i!       # Auto-increment primary key
  table_name s100     # Which table was modified
  record_id  i        # Which record was modified
  action     s20      # INSERT, UPDATE, DELETE
  old_values J?       # JSON snapshot before change
  new_values J?       # JSON snapshot after change
  changed_by s255     # User who made the change
  changed_at d        # When the change was made

  INDEX idx_audit_table (table_name)
  INDEX idx_audit_record (table_name, record_id)
  INDEX idx_audit_user (changed_by)
  INDEX idx_audit_time (changed_at)
```

### Trigger Pattern (MySQL)

```sql
CREATE TRIGGER audit_users_insert
AFTER INSERT ON users
FOR EACH ROW
INSERT INTO audit_log (table_name, record_id, action, new_values, changed_by, changed_at)
VALUES ('users', NEW.id, 'INSERT', JSON_OBJECT('email', NEW.email, 'name', NEW.name), CURRENT_USER(), NOW());
```

---

## Polymorphic Associations

Reference multiple table types from a single foreign key column.

```ss
#comments table
  id            i!
  body          S
  commentable_type s100  # Table name: 'posts', 'photos', 'videos'
  commentable_id   i     # FK to the referenced table
  author_id     i

  INDEX idx_commentable (commentable_type, commentable_id)
  FK author_id → users(id)

#posts table
  id         i!
  title      s255
  body       S
  author_id  i

  FK author_id → users(id)

#photos table
  id         i!
  url        s500
  caption    s255?
  author_id  i

  FK author_id → users(id)
```

### Query Pattern

```sql
-- Get comments for a specific post
SELECT * FROM comments
WHERE commentable_type = 'posts' AND commentable_id = 42;
```

---

## Role-Based Access Control

User roles and permissions with many-to-many relationships.

```ss
#users table
  email    s255!u
  name     s255
  password s255     # Hashed password

#roles table
  name     s50!u    # admin, editor, viewer
  description s255?

#permissions table
  name     s100!u   # posts.create, posts.edit, users.manage
  description s255?

#user_roles table
  user_id  i
  role_id  i

  FK user_id → users(id)
  FK role_id → roles(id)
  INDEX idx_user_roles_unique (user_id, role_id)!u

#role_permissions table
  role_id      i
  permission_id i

  FK role_id → roles(id)
  FK permission_id → permissions(id)
  INDEX idx_role_permissions_unique (role_id, permission_id)!u
```

---

## Multi-Language Content

Support multiple languages for content fields.

```ss
#posts table
  id         i!
  slug       s255!u
  author_id  i
  created_at d
  updated_at d

  FK author_id → users(id)

#post_translations table
  post_id    i
  locale     s10!     # en, es, fr, de, ja
  title      s255
  body       S
  excerpt    s500?

  FK post_id → posts(id)
  INDEX idx_post_locale (post_id, locale)!u
```

---

## File Upload Tracking

Track uploaded files with metadata.

```ss
#files table
  id           i!
  filename     s255     # Original filename
  storage_key  s500!u   # S3/storage path (unique)
  mime_type    s100     # MIME type
  size         N        # File size in bytes
  checksum     s64      # SHA-256 hash
  uploader_id  i
  created_at   d

  FK uploader_id → users(id)
  INDEX idx_mime_type (mime_type)
  INDEX idx_checksum (checksum)
```

---

## Rate Limiting

Track API usage per user for rate limiting.

```ss
#rate_limits table
  id          i!
  user_id     i
  endpoint    s255     # API endpoint pattern
  window_start d       # Rate limit window start
  request_count n      # Number of requests in window

  FK user_id → users(id)
  INDEX idx_rate_limit_user (user_id, endpoint, window_start)
```

---

## Feature Flags

Toggle features per tenant or globally.

```ss
#feature_flags table
  id          i!
  name        s100!u   # Feature name (e.g., 'new_checkout')
  enabled     n!       # 0=disabled, 1=enabled
  tenant_id   N?       # NULL = global, specific = tenant-specific
  config      J?       # JSON configuration for the feature
  created_at  d
  updated_at  d

  INDEX idx_feature_name (name, tenant_id)
```

---

## Schema Versioning

Track schema changes for migration history.

```ss
#schema_versions table
  id          i!
  version     s50!u    # Semantic version (1.0.0)
  description s500     # What changed
  applied_at  d        # When applied
  checksum    s64      # Schema file checksum

  INDEX idx_version (version)
```

---

## Common Type Reference

| SS Symbol | SQL Type | Description |
|-----------|----------|-------------|
| `n` | INT | Standard integer |
| `N` | BIGINT | Large integer |
| `m` | SMALLINT | Small integer |
| `i` | INT | Integer (alias for `n`) |
| `s` | VARCHAR(255) | String with default length |
| `s100` | VARCHAR(100) | String with custom length |
| `S` | TEXT | Unlimited text |
| `b` | BOOLEAN | Boolean flag |
| `d` | DATETIME | Date and time |
| `t` | TIMESTAMP | Timestamp |
| `j` | JSON | JSON data |
| `J` | JSONB | Binary JSON (PostgreSQL) |
| `U` | UUID | Universally unique identifier |
| `p` | DECIMAL(10,2) | Decimal number |

### Modifiers

| Modifier | Meaning |
|----------|---------|
| `!` | NOT NULL |
| `!u` | UNIQUE |
| `?` | Nullable |
| `u` | UNSIGNED (MySQL) |
| `PK` | Primary key |
| `AI` | Auto increment |
| `D` | Default value |

---

## Template Patterns

### Shared Timestamps

```ss
#base timestamps
  created_at d
  updated_at d
```

### Soft Delete

```ss
#base soft_delete
  is_deleted n!
  deleted_at d?
```

### Audit Fields

```ss
#base audit
  created_by s255
  updated_by s255
```

### Using Templates

```ss
#users table
  #base timestamps
  #base soft_delete
  email s255!u
  name  s255
```

---

## Customizing Generator Output (Template Overrides)

When a built-in generator's output format needs tweaking (custom header, house style, extra boilerplate), override it with a `.rune-template` file instead of forking the generator.

### Setup

Create `.rune/templates/prisma.rune-template` in your project (or `~/.rune/templates/` globally, or pass `--template-dir <dir>`):

```
// {{SCHEMA_NAME}} — generated by rune {{VERSION}} ({{DIALECT}})
generator client {
  provider = "prisma-client-js"
}

{{#TABLES}}model {{TABLE_NAME}} {
  id Int @id
}

{{/TABLES}}
```

Then generate as usual:

```bash
rune generate prisma schema.ss              # uses the template automatically
rune generate prisma schema.ss --dry-run    # preview without writing
```

### Placeholders

| Placeholder | Replaced with |
|-------------|---------------|
| `{{SCHEMA_NAME}}` | Schema name from the $ directive |
| `{{DIALECT}}` | Target dialect (`mysql`, `pg`, ...) |
| `{{VERSION}}` | Rune version |
| `{{GENERATOR}}` | Generator name (`prisma`, `drizzle`, ...) |
| `{{#TABLES}}...{{TABLE_NAME}}...{{/TABLES}}` | Expanded once per table |

Unknown `{{...}}` tokens pass through verbatim. Without a template file, built-in generator output is used unchanged.

> Note: `.rune/templates/` customizes *generator output*; `~/.rune/registry/` stores shared `%` schema-template libraries (`rune registry`). They are separate systems.

---

## Best Practices

1. **Use templates for shared fields** — Extract common patterns like timestamps, soft delete, audit fields
2. **Name foreign keys clearly** — `author_id` is better than `uid` or `ref`
3. **Add indexes for foreign keys** — FK columns should be indexed for query performance
4. **Use appropriate string lengths** — `s255` for names, `s500` for URLs, `S` for unlimited text
5. **Include timestamps** — `created_at` and `updated_at` on every table
6. **Use CHECK constraints** — Enforce valid values (e.g., status in ('draft', 'published'))
7. **Plan for multi-tenancy** — Even if not needed now, `tenant_id` is easy to add later
8. **Document with comments** — Use `# comment` to explain non-obvious columns
