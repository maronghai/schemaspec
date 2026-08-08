const std = @import("std");
const types = @import("types.zig");

const COMMAND_REGISTRY = types.COMMAND_REGISTRY;

// ─── Usage ─────────────────────────────────────────────────────

pub fn printUsage() void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("  rune [input.ss] [-o output] [--trace] [--stats] [--check] [-d mysql|pg|sqlite|mssql|oracle|db2] [--target sql|json-schema]\n", .{});
    std.debug.print("                                                       Compile .ss to SQL DDL or JSON Schema\n", .{});
    inline for (COMMAND_REGISTRY) |cmd| {
        std.debug.print("  rune {s:<32}{s}\n", .{ cmd.name ++ " " ++ cmd.args, cmd.description });
    }
    std.debug.print("                                                       -T: extract shared templates (reverse only)\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  -d, --dialect   Target SQL dialect: mysql (default), pg, postgres, sqlite, mssql, oracle, db2\n", .{});
    std.debug.print("  --target        Output format: sql (default), json-schema\n", .{});
    std.debug.print("  --format        Output format: text (default), json, sarif, markdown (for diff/migrate/stats)\n", .{});
    std.debug.print("  --trace         Print intermediate pipeline stages for debugging\n", .{});
    std.debug.print("  -s, --stats     Print compilation statistics (table/field counts)\n", .{});
    std.debug.print("  --check         Dry-run: validate schema without writing output\n", .{});
    std.debug.print("  --dry-run       Show migration SQL without writing to file\n", .{});
    std.debug.print("  --strict        Treat warnings as errors (for CI/CD)\n", .{});
    std.debug.print("  --json-errors   Output diagnostics as JSON (machine-readable)\n", .{});
    std.debug.print("  --verbose-passes Print semantic pass execution details\n", .{});
    std.debug.print("  --import-path   Additional search path for @import directives\n", .{});
    std.debug.print("  -q, --quiet     Suppress non-essential output\n", .{});
    std.debug.print("  --color         Color output: auto (default), always, never\n", .{});
    std.debug.print("  --stream        Streaming compilation (emit each table independently)\n", .{});
    std.debug.print("  --parallel      Parallel streaming compilation (use thread pool)\n", .{});
    std.debug.print("  --init          Create a starter schema file (equivalent to 'rune init')\n", .{});
    std.debug.print("  --config        Path to project config file (default: ./rune.toml)\n", .{});
    std.debug.print("  -v, --version   Print version and exit\n", .{});
    std.debug.print("  -h, --help      Show this help message and exit\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  rune schema.ss                       # Compile to MySQL DDL\n", .{});
    std.debug.print("  rune schema.ss -d pg                 # Compile to PostgreSQL\n", .{});
    std.debug.print("  rune schema.ss -d oracle             # Compile to Oracle\n", .{});
    std.debug.print("  rune schema.ss --stream              # Streaming compilation\n", .{});
    std.debug.print("  rune schema.ss --stream --parallel   # Parallel streaming compilation\n", .{});
    std.debug.print("  rune validate schema.ss              # Validate schema (no output)\n", .{});
    std.debug.print("  rune validate schema.ss -s           # Validate with stats\n", .{});
    std.debug.print("  rune --stats schema.ss               # Show compilation stats\n", .{});
    std.debug.print("  rune stats schema.ss --format json   # Stats as JSON\n", .{});
    std.debug.print("  rune --check schema.ss               # Validate without output\n", .{});
    std.debug.print("  rune diff old.ss new.ss              # Show schema differences\n", .{});
    std.debug.print("  rune diff old.ss new.ss --format json # Diff as JSON\n", .{});
    std.debug.print("  rune diff schema.ss --from-sql live.sql # Drift detection against SQL dump\n", .{});
    std.debug.print("  rune diff schema.ss --from-sql live.sql --check # CI drift gate\n", .{});
    std.debug.print("  rune diff schema.ss --from-sql - # Read SQL from stdin (pipe from mysqldump/pg_dump)\n", .{});
    std.debug.print("  rune migrate old.ss new.ss -o m.sql  # Generate migration SQL\n", .{});
    std.debug.print("  rune migrate old.ss new.ss --rollback # Generate rollback SQL\n", .{});
    std.debug.print("  rune migrate old.ss new.ss --graph    # Show migration dependency graph\n", .{});
    std.debug.print("  rune reverse schema.sql -T           # Reverse-engineer with templates\n", .{});
    std.debug.print("  rune generate json-schema schema.ss  # Generate JSON Schema from .ss\n", .{});
    std.debug.print("  rune generate --list                 # Show available generators\n", .{});
    std.debug.print("  rune init myapp                      # Create starter schema\n", .{});
    std.debug.print("  rune init myapp -d pg                # Create starter schema for PostgreSQL\n", .{});
    std.debug.print("  rune init myapp --template blog      # Create blog schema template\n", .{});
    std.debug.print("  rune hooks pre-commit               # Generate pre-commit hook\n", .{});
    std.debug.print("  rune watch schema.ss                # Watch file and recompile on change\n", .{});
    std.debug.print("  rune watch schema.ss --interval 500 # Watch with 500ms polling interval\n", .{});
    std.debug.print("  rune watch ./schemas --recursive    # Watch all .ss files in directory\n", .{});
    std.debug.print("  rune format schema.ss                  # Auto-format schema\n", .{});
    std.debug.print("\nPipe mode: read from stdin when no input file is given.\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune --target json-schema\n", .{});
    std.debug.print("  cat schema.sql | rune reverse -T\n", .{});
}

/// Print help for a specific subcommand.
pub fn printSubcommandHelp(subcommand: []const u8) void {
    std.debug.print("Usage: rune {s}", .{subcommand});
    inline for (COMMAND_REGISTRY) |cmd| {
        if (std.mem.eql(u8, cmd.name, subcommand)) {
            std.debug.print(" {s}\n", .{cmd.args});
            std.debug.print("\n{s}\n", .{cmd.description});
            if (std.mem.eql(u8, subcommand, "diff") or std.mem.eql(u8, subcommand, "migrate")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  --format        Output format: text (default), json, sarif, markdown\n", .{});
                std.debug.print("  -t, --trace     Print intermediate pipeline stages\n", .{});
                std.debug.print("  -s, --stats     Print compilation statistics\n", .{});
                std.debug.print("  --check         Exit 1 if there are differences\n", .{});
                if (std.mem.eql(u8, subcommand, "diff")) {
                    std.debug.print("  --from-sql      Compare against a SQL dump file instead of a .ss file\n", .{});
                    std.debug.print("  --summary       Show summary only (no full diff)\n", .{});
                }
                if (std.mem.eql(u8, subcommand, "migrate")) {
                    std.debug.print("  --rollback      Generate rollback SQL instead\n", .{});
                    std.debug.print("  --dry-run       Show SQL without writing to file\n", .{});
                    std.debug.print("  --summary       Show summary only (no full SQL)\n", .{});
                    std.debug.print("  --graph         Show migration dependency graph\n", .{});
                    std.debug.print("  -o, --output    Output file path\n", .{});
                }
            } else if (std.mem.eql(u8, subcommand, "reverse")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  -T, --template  Extract shared templates\n", .{});
                std.debug.print("  --format        Output format: text (default), json\n", .{});
                std.debug.print("  -t, --trace     Print intermediate pipeline stages\n", .{});
                std.debug.print("  -o, --output    Output file path\n", .{});
                std.debug.print("  --validate-only Validate SQL without generating output\n", .{});
            } else if (std.mem.eql(u8, subcommand, "generate")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  --list, -l      List available generators\n", .{});
                std.debug.print("  -o, --output    Output file path\n", .{});
                std.debug.print("\nRun 'rune generate --list' to see available generators.\n", .{});
            } else if (std.mem.eql(u8, subcommand, "validate") or std.mem.eql(u8, subcommand, "check")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  -s, --stats     Print compilation statistics\n", .{});
                std.debug.print("  --verbose-passes Print semantic pass execution details\n", .{});
            } else if (std.mem.eql(u8, subcommand, "init")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  -d, --dialect   Target dialect: mysql (default), pg, sqlite, mssql, oracle, db2\n", .{});
                std.debug.print("  -o, --output    Output file path\n", .{});
                std.debug.print("  --output-dir    Output directory (creates if needed)\n", .{});
                std.debug.print("  --template      Schema template: default (default), blog, ecommerce, rest-api\n", .{});
                std.debug.print("\nExamples:\n", .{});
                std.debug.print("  rune init myapp                      # Default starter schema\n", .{});
                std.debug.print("  rune init myapp --template blog      # Blog schema (posts, categories, tags)\n", .{});
                std.debug.print("  rune init myapp --template ecommerce # E-commerce schema (products, orders)\n", .{});
                std.debug.print("  rune init myapp --template rest-api  # REST API schema (resources, api keys)\n", .{});
            } else if (std.mem.eql(u8, subcommand, "completions")) {
                std.debug.print("\nArguments:\n", .{});
                std.debug.print("  shell           Target shell: bash (default), zsh, fish, powershell\n", .{});
            } else if (std.mem.eql(u8, subcommand, "hooks")) {
                std.debug.print("\nArguments:\n", .{});
                std.debug.print("  type            Hook type: pre-commit (default)\n", .{});
                std.debug.print("\nInstall:\n", .{});
                std.debug.print("  rune hooks pre-commit > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit\n", .{});
            } else if (std.mem.eql(u8, subcommand, "lint")) {
                std.debug.print("\nChecks schema for quality issues and anti-patterns:\n", .{});
                std.debug.print("  no-pk            Table has no primary key\n", .{});
                std.debug.print("  naming           Table/column name uses camelCase instead of snake_case\n", .{});
                std.debug.print("  no-index-fk      Foreign key column has no index\n", .{});
                std.debug.print("  no-timestamps    No created_at/updated_at fields\n", .{});
                std.debug.print("  wide-table       Table has more than 30 fields (configurable)\n", .{});
                std.debug.print("  enum-case        Custom type uses non-UPPER_CASE naming\n", .{});
                std.debug.print("  count            Table has fewer than 2 non-PK fields (configurable)\n", .{});
                std.debug.print("  fk-cascade       FK has no explicit ON DELETE/ON UPDATE actions\n", .{});
                std.debug.print("  nullable-pk      Primary key column is nullable\n", .{});
                std.debug.print("  orphan-type      Custom type is defined but never used by any table\n", .{});
                std.debug.print("  index-unused     Standalone index may be unnecessary\n", .{});
                std.debug.print("  circular-fk      Foreign key chain forms a circular reference\n", .{});
                std.debug.print("  duplicate-index  Multiple indexes with same columns and type\n", .{});
                std.debug.print("  empty-table      Table has no fields defined\n", .{});
                std.debug.print("  table-comment    Table lacks a comment/documentation\n", .{});
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  --json-errors  Output results as JSON (machine-readable)\n", .{});
                std.debug.print("  --strict       Exit 1 if any warnings found (for CI/CD)\n", .{});
                std.debug.print("  --format       Output format: text (default), json, sarif\n", .{});
                std.debug.print("  --rules        Path to rune-lint.toml rules file\n", .{});
                std.debug.print("\nExamples:\n", .{});
                std.debug.print("  rune lint schema.ss                # Lint schema\n", .{});
                std.debug.print("  rune lint schema.ss --json-errors  # Lint as JSON\n", .{});
                std.debug.print("  rune lint schema.ss --strict       # Lint, exit 1 on warnings\n", .{});
                std.debug.print("  rune lint old.ss new.ss            # Diff-aware lint (new issues only)\n", .{});
            } else if (std.mem.eql(u8, subcommand, "watch")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  --interval      Polling interval in milliseconds (default: 1000)\n", .{});
                std.debug.print("  --recursive     Watch directory recursively for all .ss files\n", .{});
                std.debug.print("  --parallel      Parallel streaming compilation\n", .{});
                std.debug.print("  -d, --dialect   Target SQL dialect\n", .{});
                std.debug.print("  --target        Output format: sql (default), json-schema\n", .{});
                std.debug.print("  -o, --output    Output file path\n", .{});
                std.debug.print("  -t, --trace     Print intermediate pipeline stages\n", .{});
                std.debug.print("  -s, --stats     Print compilation statistics\n", .{});
                std.debug.print("  --json-errors   Output diagnostics as JSON\n", .{});
                std.debug.print("\nExamples:\n", .{});
                std.debug.print("  rune watch schema.ss                  # Watch with default 1s interval\n", .{});
                std.debug.print("  rune watch schema.ss --interval 500   # Watch with 500ms interval\n", .{});
                std.debug.print("  rune watch schema.ss -d pg            # Watch and compile to PostgreSQL\n", .{});
                std.debug.print("  rune watch schema.ss -o out.sql       # Watch and write to file\n", .{});
                std.debug.print("  rune watch schema.ss --parallel       # Watch with parallel compilation\n", .{});
                std.debug.print("  rune watch schema.ss -s               # Watch with compilation stats\n", .{});
                std.debug.print("  rune watch ./schemas --recursive      # Watch all .ss files in directory\n", .{});
                std.debug.print("\nPress Ctrl+C to stop watching.\n", .{});
            } else {
                std.debug.print("\nGlobal options also apply: -d/--dialect, -s/--stats, -q/--quiet, -h/--help\n", .{});
            }
            return;
        }
    }
    std.debug.print("\nUnknown command: {s}\n", .{subcommand});
}
