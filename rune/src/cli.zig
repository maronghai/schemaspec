const std = @import("std");
const dialect_enum = @import("dialect/enum.zig");

// ─── Command Types ─────────────────────────────────────────────

pub const Target = enum { sql, json_schema };

pub const DiffFormat = enum { text, json, sarif };

pub const Command = union(enum) {
    compile: struct { input: ?[]const u8, output: ?[]const u8, trace: bool, stats: bool, check: bool, verbose_passes: bool },
    validate: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    check: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    diff: struct { old: []const u8, new: []const u8, trace: bool, stats: bool, format: DiffFormat, check: bool },
    migrate: struct { old: []const u8, new: []const u8, output: ?[]const u8, trace: bool, rollback: bool, stats: bool, dry_run: bool, format: DiffFormat, check: bool },
    reverse: struct { input: ?[]const u8, output: ?[]const u8, with_templates: bool, trace: bool, stats: bool, validate_only: bool },
    docs: struct { input: ?[]const u8, output: ?[]const u8 },
    generate: struct { generator: []const u8, input: ?[]const u8, output: ?[]const u8, list: bool },
    version,
    help,
};

pub const ParsedArgs = struct {
    dialect: dialect_enum.Dialect,
    target: Target,
    command: Command,
    quiet: bool,
    strict: bool,
    json_errors: bool = false,
    import_paths: []const []const u8 = &.{},
};

pub const ArgError = error{
    UnknownDialect,
    MissingDialectValue,
    UnknownTarget,
    MissingTargetValue,
    UnknownFormat,
    UnknownCommand,
    UnknownFlag,
    DiffMissingArgs,
    MigrateMissingArgs,
};

/// Last unknown flag detected by parseArgs. Valid only when parseArgs returns error.UnknownFlag.
pub var last_unknown_flag: ?[]const u8 = null;

// ─── Shared Flag Parsers ───────────────────────────────────────

/// Scan args for `--rollback` and return true if found.
fn parseRollbackFlag(args: []const []const u8, start: usize) bool {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "--rollback")) {
            return true;
        }
    }
    return false;
}

/// Scan args for `-o <path>` and return the output path (or null).
fn parseOutputFlag(args: []const []const u8, start: usize) ?[]const u8 {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "-o") and j + 1 < args.len) {
            const val = args[j + 1];
            // Reject if value starts with '-' (likely a missing value)
            if (val.len > 0 and val[0] == '-') return null;
            return val;
        }
    }
    return null;
}

/// Scan args for `-t` or `--trace` and return true if found.
fn parseTraceFlag(args: []const []const u8, start: usize) bool {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "-t") or std.mem.eql(u8, args[j], "--trace")) {
            return true;
        }
    }
    return false;
}

// ─── Argument Parsing ──────────────────────────────────────────

pub fn parseArgs(alloc: std.mem.Allocator, raw_args: []const []const u8) !ParsedArgs {
    var dialect: dialect_enum.Dialect = .mysql;
    var target: Target = .sql;
    var filtered = try std.ArrayList([]const u8).initCapacity(alloc, raw_args.len);

    // Pass 1: extract global flags from all args
    var i: usize = 1; // skip argv[0]
    var want_version = false;
    var want_help = false;
    var want_stats = false;
    var want_quiet = false;
    var want_check = false;
    var want_dry_run = false;
    var want_strict = false;
    var want_verbose_passes = false;
    var want_json_errors = false;
    var diff_format: DiffFormat = .text;
    var import_paths = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    var want_validate_only = false;
    while (i < raw_args.len) : (i += 1) {
        if (std.mem.eql(u8, raw_args[i], "--version") or std.mem.eql(u8, raw_args[i], "-v")) {
            want_version = true;
        } else if (std.mem.eql(u8, raw_args[i], "--help") or std.mem.eql(u8, raw_args[i], "-h")) {
            want_help = true;
        } else if (std.mem.eql(u8, raw_args[i], "--stats") or std.mem.eql(u8, raw_args[i], "-s")) {
            want_stats = true;
        } else if (std.mem.eql(u8, raw_args[i], "--quiet") or std.mem.eql(u8, raw_args[i], "-q")) {
            want_quiet = true;
        } else if (std.mem.eql(u8, raw_args[i], "--check")) {
            want_check = true;
        } else if (std.mem.eql(u8, raw_args[i], "--dry-run")) {
            want_dry_run = true;
        } else if (std.mem.eql(u8, raw_args[i], "--dialect") or std.mem.eql(u8, raw_args[i], "-d")) {
            if (i + 1 < raw_args.len) {
                dialect = parseDialect(raw_args[i + 1]) catch |e| {
                    if (e == error.UnknownDialect) return error.UnknownDialect;
                    return error.MissingDialectValue;
                };
                i += 1; // skip dialect value
            } else {
                return error.MissingDialectValue;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--target")) {
            if (i + 1 < raw_args.len) {
                target = parseTarget(raw_args[i + 1]) catch |e| {
                    if (e == error.UnknownTarget) return error.UnknownTarget;
                    return error.MissingTargetValue;
                };
                i += 1; // skip target value
            } else {
                return error.MissingTargetValue;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--format")) {
            if (i + 1 < raw_args.len) {
                if (std.mem.eql(u8, raw_args[i + 1], "json")) {
                    diff_format = .json;
                } else if (std.mem.eql(u8, raw_args[i + 1], "sarif")) {
                    diff_format = .sarif;
                } else if (!std.mem.eql(u8, raw_args[i + 1], "text")) {
                    return error.UnknownFormat;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--validate-only")) {
            want_validate_only = true;
        } else if (std.mem.eql(u8, raw_args[i], "--strict")) {
            want_strict = true;
        } else if (std.mem.eql(u8, raw_args[i], "--json-errors")) {
            want_json_errors = true;
        } else if (std.mem.eql(u8, raw_args[i], "--verbose-passes")) {
            want_verbose_passes = true;
        } else if (std.mem.eql(u8, raw_args[i], "--import-path")) {
            if (i + 1 < raw_args.len) {
                try import_paths.append(alloc, raw_args[i + 1]);
                i += 1;
            }
        } else {
            // Reject unrecognized long flags (--something)
            if (raw_args[i].len > 2 and raw_args[i][0] == '-' and raw_args[i][1] == '-' and !isKnownLongFlag(raw_args[i])) {
                last_unknown_flag = raw_args[i];
                return error.UnknownFlag;
            }
            try filtered.append(alloc, raw_args[i]);
        }
    }
    const fargs = try filtered.toOwnedSlice(alloc);
    const import_path_list = try import_paths.toOwnedSlice(alloc);

    if (want_version) {
        return .{ .dialect = dialect, .target = target, .command = .version, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list };
    }

    if (want_help) {
        return .{ .dialect = dialect, .target = target, .command = .help, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list };
    }

    const flags = GlobalFlags{
        .stats = want_stats,
        .check = want_check,
        .dry_run = want_dry_run,
        .strict = want_strict,
        .verbose_passes = want_verbose_passes,
        .json_errors = want_json_errors,
        .format = diff_format,
        .validate_only = want_validate_only,
        .quiet = want_quiet,
        .import_paths = import_path_list,
    };

    // No positional args, or first arg is a flag → default compile from stdin
    if (fargs.len < 1 or (fargs.len > 0 and fargs[0][0] == '-')) {
        return .{
            .dialect = dialect,
            .target = target,
            .command = .{ .compile = .{
                .input = null,
                .output = parseOutputFlag(fargs, 0),
                .trace = parseTraceFlag(fargs, 0),
                .stats = want_stats,
                .check = want_check,
                .verbose_passes = want_verbose_passes,
            } },
            .quiet = want_quiet,
            .strict = want_strict,
            .json_errors = want_json_errors,
            .import_paths = import_path_list,
        };
    }

    const sub = fargs[0];

    if (std.mem.eql(u8, sub, "diff")) return parseDiffArgs(fargs, dialect, target, flags);
    if (std.mem.eql(u8, sub, "migrate")) return parseMigrateArgs(fargs, dialect, target, flags);
    if (std.mem.eql(u8, sub, "reverse")) return parseReverseArgs(fargs, dialect, target, flags);
    if (std.mem.eql(u8, sub, "generate")) return parseGenerateArgs(fargs, dialect, target, flags);

    if (std.mem.eql(u8, sub, "validate")) {
        const input = if (fargs.len > 1) fargs[1] else null;
        return parseSimpleSubcommand(dialect, target, .{ .validate = .{ .input = input, .stats = want_stats, .verbose_passes = want_verbose_passes } }, flags);
    }

    if (std.mem.eql(u8, sub, "check")) {
        const input = if (fargs.len > 1) fargs[1] else null;
        return parseSimpleSubcommand(dialect, target, .{ .check = .{ .input = input, .stats = want_stats, .verbose_passes = want_verbose_passes } }, flags);
    }

    if (std.mem.eql(u8, sub, "docs")) {
        const input = if (fargs.len > 1) fargs[1] else null;
        return parseSimpleSubcommand(dialect, target, .{ .docs = .{ .input = input, .output = parseOutputFlag(fargs, 1) } }, flags);
    }

    // Unknown command detection
    if (fargs.len > 0 and std.mem.indexOfScalar(u8, fargs[0], '.') == null) {
        if (!isKnownCommand(fargs[0]) and !std.mem.eql(u8, fargs[0], "-")) {
            return error.UnknownCommand;
        }
    }

    // Default: compile
    const input = if (fargs.len > 0) fargs[0] else null;
    return .{
        .dialect = dialect,
        .target = target,
        .command = .{ .compile = .{
            .input = input,
            .output = parseOutputFlag(fargs, 1),
            .trace = parseTraceFlag(fargs, 1),
            .stats = want_stats,
            .check = want_check,
            .verbose_passes = want_verbose_passes,
        } },
        .quiet = want_quiet,
        .strict = want_strict,
        .json_errors = want_json_errors,
        .import_paths = import_path_list,
    };
}

fn parseDialect(s: []const u8) !dialect_enum.Dialect {
    if (std.mem.eql(u8, s, "mysql")) return .mysql;
    if (std.mem.eql(u8, s, "pg") or std.mem.eql(u8, s, "postgres")) return .pg;
    if (std.mem.eql(u8, s, "sqlite") or std.mem.eql(u8, s, "sq")) return .sqlite;
    if (std.mem.eql(u8, s, "mssql") or std.mem.eql(u8, s, "sqlserver")) return .mssql;
    return error.UnknownDialect;
}

fn parseTarget(s: []const u8) !Target {
    if (std.mem.eql(u8, s, "sql")) return .sql;
    if (std.mem.eql(u8, s, "json-schema") or std.mem.eql(u8, s, "json_schema")) return .json_schema;
    return error.UnknownTarget;
}

// ─── Command Registry ─────────────────────────────────────────
// Table-driven command definitions for auto-generated help and unknown command detection.
// To add a new command: add an entry here + a branch in the routing below.

const CommandInfo = struct {
    name: []const u8,
    args: []const u8, // argument syntax (e.g. "<old.ss> <new.ss>")
    description: []const u8,
};

const COMMAND_REGISTRY = [_]CommandInfo{
    .{ .name = "validate", .args = "[input.ss]", .description = "Validate .ss schema (no output)" },
    .{ .name = "check", .args = "[input.ss]", .description = "Check schema validity (exit 1 on error)" },
    .{ .name = "diff", .args = "<old.ss> <new.ss>", .description = "Show schema differences" },
    .{ .name = "migrate", .args = "<old.ss> <new.ss>", .description = "Generate ALTER TABLE migration SQL" },
    .{ .name = "reverse", .args = "[input.sql]", .description = "Reverse SQL DDL to .ss schema" },
    .{ .name = "docs", .args = "[input.ss]", .description = "Generate Markdown documentation" },
    .{ .name = "generate", .args = "<generator> [input.ss]", .description = "Generate output in specified format" },
};

/// Check if a long flag (--flag) is recognized by the parser.
fn isKnownLongFlag(flag: []const u8) bool {
    const known = [_][]const u8{
        "--version",        "--help",        "--stats",  "--quiet",         "--check",  "--dry-run",
        "--dialect",        "--target",      "--format", "--validate-only", "--strict", "--json-errors",
        "--verbose-passes", "--import-path", "--trace",  "--rollback",      "--output", "--list",
    };
    inline for (known) |k| {
        if (std.mem.eql(u8, flag, k)) return true;
    }
    return false;
}

/// Check if a string is a known subcommand name.
fn isKnownCommand(name: []const u8) bool {
    for (COMMAND_REGISTRY) |cmd| {
        if (std.mem.eql(u8, name, cmd.name)) return true;
    }
    return false;
}

// ─── Subcommand Parsers ──────────────────────────────────────

fn parseDiffArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    if (fargs.len < 3) return error.DiffMissingArgs;
    return .{
        .dialect = dialect,
        .target = target,
        .command = .{ .diff = .{
            .old = fargs[1],
            .new = fargs[2],
            .trace = parseTraceFlag(fargs, 3),
            .stats = opts.stats,
            .format = opts.format,
            .check = opts.check,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
    };
}

fn parseMigrateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    if (fargs.len < 3) return error.MigrateMissingArgs;
    return .{
        .dialect = dialect,
        .target = target,
        .command = .{ .migrate = .{
            .old = fargs[1],
            .new = fargs[2],
            .output = parseOutputFlag(fargs, 3),
            .trace = parseTraceFlag(fargs, 3),
            .rollback = parseRollbackFlag(fargs, 3),
            .stats = opts.stats,
            .dry_run = opts.dry_run,
            .format = opts.format,
            .check = opts.check,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
    };
}

fn parseReverseArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    var with_templates = false;
    var input: ?[]const u8 = null;
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "-T") or std.mem.eql(u8, fargs[j], "--template")) {
            with_templates = true;
        } else if (input == null) {
            input = fargs[j];
        }
    }
    return .{
        .dialect = dialect,
        .target = target,
        .command = .{ .reverse = .{
            .input = input,
            .output = parseOutputFlag(fargs, 1),
            .with_templates = with_templates,
            .trace = parseTraceFlag(fargs, 1),
            .stats = opts.stats,
            .validate_only = opts.validate_only,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
    };
}

fn parseGenerateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    var want_list = false;
    var generator: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--list") or std.mem.eql(u8, fargs[j], "-l")) {
            want_list = true;
        } else if (generator == null) {
            generator = fargs[j];
        } else if (input == null) {
            input = fargs[j];
        }
    }
    return .{
        .dialect = dialect,
        .target = target,
        .command = .{ .generate = .{
            .generator = generator orelse "",
            .input = input,
            .output = parseOutputFlag(fargs, 1),
            .list = want_list,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
    };
}

/// Flags extracted from the global pass (shared by all subcommands).
const GlobalFlags = struct {
    stats: bool,
    check: bool,
    dry_run: bool,
    strict: bool,
    verbose_passes: bool,
    json_errors: bool,
    format: DiffFormat,
    validate_only: bool,
    quiet: bool,
    import_paths: []const []const u8,
};

/// Shared single-argument subcommand builder (validate, check, docs).
fn parseSimpleSubcommand(dialect: dialect_enum.Dialect, target: Target, cmd: Command, opts: GlobalFlags) ParsedArgs {
    return .{
        .dialect = dialect,
        .target = target,
        .command = cmd,
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
    };
}

// ─── Usage ─────────────────────────────────────────────────────

pub fn printUsage() void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("  rune [input.ss] [-o output] [--trace] [--stats] [--check] [-d mysql|pg|sqlite|mssql] [--target sql|json-schema]\n", .{});
    std.debug.print("                                                       Compile .ss to SQL DDL or JSON Schema\n", .{});
    inline for (COMMAND_REGISTRY) |cmd| {
        std.debug.print("  rune {s:<32}{s}\n", .{ cmd.name ++ " " ++ cmd.args, cmd.description });
    }
    std.debug.print("                                                       -T: extract shared templates (reverse only)\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  -d, --dialect   Target SQL dialect: mysql (default), pg, postgres, sqlite, mssql\n", .{});
    std.debug.print("  --target        Output format: sql (default), json-schema\n", .{});
    std.debug.print("  --format        Output format: text (default), json, sarif (for diff/migrate)\n", .{});
    std.debug.print("  --trace         Print intermediate pipeline stages for debugging\n", .{});
    std.debug.print("  -s, --stats     Print compilation statistics (table/field counts)\n", .{});
    std.debug.print("  --check         Dry-run: validate schema without writing output\n", .{});
    std.debug.print("  --dry-run       Show migration SQL without writing to file\n", .{});
    std.debug.print("  --strict        Treat warnings as errors (for CI/CD)\n", .{});
    std.debug.print("  --json-errors   Output diagnostics as JSON (machine-readable)\n", .{});
    std.debug.print("  --verbose-passes Print semantic pass execution details\n", .{});
    std.debug.print("  --import-path   Additional search path for @import directives\n", .{});
    std.debug.print("  -q, --quiet     Suppress non-essential output\n", .{});
    std.debug.print("  -v, --version   Print version and exit\n", .{});
    std.debug.print("  -h, --help      Show this help message and exit\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  rune schema.ss                       # Compile to MySQL DDL\n", .{});
    std.debug.print("  rune schema.ss -d pg                 # Compile to PostgreSQL\n", .{});
    std.debug.print("  rune --stats schema.ss               # Show compilation stats\n", .{});
    std.debug.print("  rune --check schema.ss               # Validate without output\n", .{});
    std.debug.print("  rune diff old.ss new.ss              # Show schema differences\n", .{});
    std.debug.print("  rune migrate old.ss new.ss -o m.sql  # Generate migration SQL\n", .{});
    std.debug.print("  rune reverse schema.sql -T           # Reverse-engineer with templates\n", .{});
    std.debug.print("  rune generate json-schema schema.ss  # Generate JSON Schema from .ss\n", .{});
    std.debug.print("  rune generate --list                 # Show available generators\n", .{});
    std.debug.print("\nPipe mode: read from stdin when no input file is given.\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune --target json-schema\n", .{});
    std.debug.print("  cat schema.sql | rune reverse -T\n", .{});
}
