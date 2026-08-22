const std = @import("std");
const types = @import("types.zig");

const COMMAND_REGISTRY = types.COMMAND_REGISTRY;
const COMMAND_HELP = types.COMMAND_HELP;

// ─── Usage ─────────────────────────────────────────────────────

pub fn printUsage() void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("  rune [input.ss] [-o output] [--trace] [--stats] [--check] [-d mysql|pg|sqlite|mssql|oracle|db2] [--target sql|json-schema]\n", .{});
    std.debug.print("                                                       Compile .ss to SQL DDL or JSON Schema\n", .{});
    inline for (COMMAND_REGISTRY) |cmd| {
        std.debug.print("  rune {s:<32}{s}\n", .{ cmd.name ++ " " ++ cmd.args, cmd.description });
    }
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
    std.debug.print("  --cache         Enable table-level compilation cache (incremental)\n", .{});
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
    std.debug.print("  rune schema.ss --stream --cache      # Streaming with cache (incremental)\n", .{});
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
    std.debug.print("  rune tune schema.ss                    # Extract common fields into templates\n", .{});
    std.debug.print("\nPipe mode: read from stdin when no input file is given.\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune --target json-schema\n", .{});
    std.debug.print("  cat schema.sql | rune reverse -T\n", .{});
}

/// Print help for a specific subcommand.
/// Uses data-driven COMMAND_HELP registry — no per-command if-else chain.
pub fn printSubcommandHelp(subcommand: []const u8) void {
    std.debug.print("Usage: rune {s}", .{subcommand});

    // Find help details in the registry
    inline for (COMMAND_REGISTRY) |cmd| {
        if (std.mem.eql(u8, cmd.name, subcommand)) {
            std.debug.print(" {s}\n", .{cmd.args});
            std.debug.print("\n{s}\n", .{cmd.description});

            // Look up the COMMAND_HELP entry by command name (NOT by array
            // position — position-coupling silently drifted and rendered the
            // wrong command's options). The comptime coverage check in
            // types.zig guarantees exactly one entry per registry command.
            const help = findHelp(&COMMAND_HELP, subcommand);
            if (help) |h| {
                if (h.options.len > 0) {
                    std.debug.print("\nOptions:\n", .{});
                    for (h.options) |opt| {
                        std.debug.print("{s}\n", .{opt});
                    }
                }
                if (h.examples.len > 0) {
                    std.debug.print("\nExamples:\n", .{});
                    for (h.examples) |ex| {
                        std.debug.print("{s}\n", .{ex});
                    }
                }
            }
            return;
        }
    }
    std.debug.print("\nUnknown command: {s}\n", .{subcommand});
}

/// Find a COMMAND_HELP entry by its `.command` name key.
fn findHelp(entries: []const types.CommandHelp, name: []const u8) ?types.CommandHelp {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.command, name)) return entry;
    }
    return null;
}
