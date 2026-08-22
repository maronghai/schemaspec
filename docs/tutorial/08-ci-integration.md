# Lesson 8: CI/CD Integration

**Duration**: 15 minutes

## Objective

Integrate Rune into your CI/CD pipeline for schema validation, migration generation, and drift detection.

## Validation Commands

### `rune validate` — Full Validation with Stats

```bash
rune validate schema.ss              # validate, no output on success
rune validate schema.ss -s           # with compilation stats
rune validate schema.ss --fix        # auto-fix lint issues
rune validate schema.ss --format json # JSON output for tooling
rune validate schema.ss --format sarif # SARIF for GitHub Code Scanning
```

Exit codes: `0` = valid, `1` = errors found.

### `rune check` — CI Gate (Exit 1 on Error)

```bash
rune check schema.ss                 # exit 1 if any errors
rune check schema.ss --strict        # treat warnings as errors
rune check schema.ss --format json   # machine-readable
```

Use in CI:
```yaml
- name: Validate schema
  run: rune check schema.ss --strict
```

## Linting

```bash
rune lint schema.ss                  # show warnings
rune lint schema.ss --fix            # auto-fix (11 fixable rules)
rune lint schema.ss --fix --dry-run  # preview fixes
rune lint schema.ss --strict         # exit 1 on warnings
rune lint schema.ss --json-errors    # JSON output
rune lint --show-rules               # list all 84 rules
rune lint --init                     # generate .rune-lint.toml config
```

### Lint Config (`.rune-lint.toml`)

```toml
[rule.column-no-comment]
level = "warning"

[rule.table-comment]
level = "error"

[rule.no-pk]
level = "off"
```

## Schema Diff

```bash
rune diff old.ss new.ss              # human-readable diff
rune diff old.ss new.ss --format json # structured diff
rune diff old.ss new.ss --format sarif # SARIF for PR comments
rune diff old.ss new.ss --check      # exit 1 if differences (CI gate)
rune diff old.ss new.ss --summary    # N changed, X added, Y dropped
rune diff schema.ss --from-sql live.sql # drift detection vs live DB
```

### Drift Detection

```bash
# Dump live DB schema
mysqldump -d -u$user -p$pass dbname > live.sql

# Compare .ss against live
rune diff schema.ss --from-sql live.sql --check
# exit 1 = drift detected
```

## Migration Generation

```bash
rune migrate old.ss new.ss           # forward migration SQL
rune migrate old.ss new.ss --rollback # rollback SQL
rune migrate old.ss new.ss -o migration.sql
rune migrate old.ss new.ss --incremental # incremental migration files
rune migrate old.ss new.ss --name add_user_bio # named migration
rune migrate old.ss new.ss --dir migrations/ # output to directory
rune migrate --graph migrations/     # dependency graph
rune migrate status migrations/      # applied/pending status
```

### Incremental Migrations

```bash
# Generate sequentially numbered files
rune migrate v1.ss v2.ss --incremental --dir migrations/
# Creates: migrations/0001_add_users.sql, 0002_add_posts.sql, ...
```

### Migration Status

```bash
rune migrate status migrations/ --json
```

```json
{
  "applied": ["0001_add_users", "0002_add_posts"],
  "pending": ["0003_add_bio"],
  "total": 3
}
```

## GitHub Actions

### Validate on PR

```yaml
# .github/workflows/schema.yml
name: Schema Validation
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Rune
        run: |
          curl -fsSL https://github.com/rune-lang/rune/releases/latest/download/rune-linux-amd64.tar.gz | tar xz
          sudo mv rune /usr/local/bin/
      - name: Validate schema
        run: rune check schema.ss --strict
      - name: Lint schema
        run: rune lint schema.ss --strict
      - name: Check drift
        if: github.event_name == 'pull_request'
        run: |
          mysqldump -d -h ${{ secrets.DB_HOST }} -u ${{ secrets.DB_USER }} -p${{ secrets.DB_PASS }} ${{ secrets.DB_NAME }} > live.sql
          rune diff schema.ss --from-sql live.sql --check
```

### Auto-generate Migrations

```yaml
# .github/workflows/migrate.yml
name: Generate Migration
on:
  push:
    branches: [main]
    paths: ['schema.ss']
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # need history for diff
      - name: Install Rune
        run: curl -fsSL https://github.com/rune-lang/rune/releases/latest/download/rune-linux-amd64.tar.gz | tar xz && sudo mv rune /usr/local/bin/
      - name: Generate migration
        run: |
          git show HEAD~1:schema.ss > old.ss
          rune migrate old.ss schema.ss --incremental --dir migrations/
      - name: Commit migration
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add migrations/
          git commit -m "chore: add migration $(date +%Y%m%d)"
          git push
```

## Pre-commit Hook

```bash
# Generate hook
rune init --hook pre-commit > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Or use `pre-commit` framework:
```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: rune-validate
        name: Rune Validate
        entry: rune check schema.ss --strict
        language: system
        files: '\.ss$'
      - id: rune-lint
        name: Rune Lint
        entry: rune lint schema.ss
        language: system
        files: '\.ss$'
```

## Watch Mode (Development)

```bash
rune watch schema.ss                  # recompile on change
rune watch schema.ss --stream         # streaming compilation
rune watch schema.ss --parallel       # parallel compilation
rune watch schemas/ --recursive       # watch directory
rune watch schema.ss -s               # with stats
```

## Exercise

Create a complete CI pipeline:

1. **Validate + Lint** on every PR
2. **Drift detection** against staging DB
3. **Auto-generate migrations** on merge to main
4. **Deploy migrations** via your deployment pipeline

```bash
# Test locally
rune check schema.ss --strict
rune lint schema.ss --strict
rune diff schema.ss --from-sql staging_dump.sql --check
rune migrate v1.ss schema.ss --incremental --dir migrations/
```

## Key Takeaways

- `rune check --strict` — CI gate for validity
- `rune lint --strict` — CI gate for quality
- `rune diff --check` — detect schema changes
- `rune diff --from-sql live.sql --check` — drift detection
- `rune migrate --incremental --dir migrations/` — versioned migration files
- `rune migrate status` — track applied/pending
- GitHub Actions: validate on PR, generate migrations on merge
- Pre-commit hooks: catch issues before commit
- `rune watch` — hot reload during development

---

## Tutorial Complete! 🎉

You've learned:
1. **Schema Basics** — `$`, `#`, type symbols, modifiers
2. **Custom Types** — `~` aliases with dialect overrides
3. **Templates** — `%` with `...` slots and mixin inheritance
4. **Foreign Keys** — inline, standalone, actions, autofk
5. **Indexes & Constraints** — `@`, `@u`, `!`, CHECK, generated columns
6. **Views & Conditionals** — `&` views, `@if(dialect=)`, `@version`
7. **Generators** — 12 generators for ORMs, APIs, docs
8. **CI/CD** — validate, lint, diff, migrate, drift detection

### Next Steps

- Explore `schemaspec/schema.md` for complete language reference
- Read `schemaspec/type.md` for full type system details
- Check `docs/coverage-matrix.md` for generator/dialect support
- Join the community: GitHub Discussions, Discord
- Contribute: RFC process, bug reports, generator plugins

**Happy schema designing!**
