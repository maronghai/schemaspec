const std = @import("std");
const dialect_enum = @import("dialect/enum.zig");

// ─── Command Types ─────────────────────────────────────────────

pub const Target = enum { sql, json_schema };

pub const DiffFormat = enum { text, json, sarif, markdown };

pub const StatsFormat = enum { text, json };

pub const Command = union(enum) {
    compile: struct { input: ?[]const u8, output: ?[]const u8, trace: bool, stats: bool, check: bool, verbose_passes: bool },
    validate: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    check: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    stats: struct { input: ?[]const u8, format: StatsFormat = .text },
    diff: struct { old: []const u8, new: []const u8, trace: bool, stats: bool, format: DiffFormat, check: bool, summary: bool = false },
    migrate: struct { old: []const u8, new: []const u8, output: ?[]const u8, trace: bool, rollback: bool, stats: bool, dry_run: bool, format: DiffFormat, check: bool, name: ?[]const u8, dir: ?[]const u8, incremental: bool, summary: bool = false },
    migrate_status: struct { dir: ?[]const u8, json_errors: bool = false },
    reverse: struct { input: ?[]const u8, output: ?[]const u8, with_templates: bool, trace: bool, stats: bool, validate_only: bool, format: DiffFormat },
    docs: struct { input: ?[]const u8, output: ?[]const u8 },
    format_cmd: struct { input: ?[]const u8, output: ?[]const u8 },
    generate: struct { generator: []const u8, input: ?[]const u8, output: ?[]const u8, list: bool },
    init: struct { name: ?[]const u8, output: ?[]const u8 },
    completions: struct { shell: []const u8 },
    version,
    help: struct { subcommand: ?[]const u8 = null },
};

pub const ParsedArgs = struct {
    dialect: dialect_enum.Dialect,
    target: Target,
    command: Command,
    quiet: bool,
    strict: bool,
    json_errors: bool = false,
    import_paths: []const []const u8 = &.{},
    color: ColorMode = .auto,
    init_flag: bool = false,
    config_path: ?[]const u8 = null,
};

pub const ColorMode = enum {
    auto,
    always,
    never,

    /// Determine if color should be used. For `auto`, checks if stdout is a TTY.
    pub fn shouldUseColor(self: ColorMode, io: std.Io) bool {
        return switch (self) {
            .always => true,
            .never => false,
            .auto => std.Io.File.stdout().isTty(io) catch false,
        };
    }
};

pub const ArgError = error{
    UnknownDialect,
    MissingDialectValue,
    UnknownTarget,
    MissingTargetValue,
    UnknownFormat,
    UnknownCommand,
    UnknownFlag,
    UnknownGenerator,
    DiffMissingArgs,
    MigrateMissingArgs,
};

/// Find the first unrecognized long flag in raw args. Returns null if all flags are known.
pub fn findUnknownFlag(raw_args: []const []const u8) ?[]const u8 {
    var i: usize = 1;
    while (i < raw_args.len) : (i += 1) {
        const arg = raw_args[i];
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-' and !isKnownLongFlag(arg)) {
            return arg;
        }
    }
    return null;
}

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

/// Scan args for `-o <path>` or `--output <path>` and return the output path (or null).
fn parseOutputFlag(args: []const []const u8, start: usize) ?[]const u8 {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if ((std.mem.eql(u8, args[j], "-o") or std.mem.eql(u8, args[j], "--output")) and j + 1 < args.len) {
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

/// Check if args contain `-h` or `--help`.
fn hasHelpFlag(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) return true;
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
    var want_stats = false;
    var want_quiet = false;
    var want_check = false;
    var want_dry_run = false;
    var want_strict = false;
    var want_verbose_passes = false;
    var want_json_errors = false;
    var want_color: ColorMode = .auto;
    var want_init = false;
    var want_summary = false;
    var config_path: ?[]const u8 = null;
    var diff_format: DiffFormat = .text;
    var import_paths = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    var want_validate_only = false;
    while (i < raw_args.len) : (i += 1) {
        if (std.mem.eql(u8, raw_args[i], "--version") or std.mem.eql(u8, raw_args[i], "-v")) {
            want_version = true;
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
                } else if (std.mem.eql(u8, raw_args[i + 1], "markdown")) {
                    diff_format = .markdown;
                } else if (!std.mem.eql(u8, raw_args[i + 1], "text")) {
                    return error.UnknownFormat;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--validate-only")) {
            want_validate_only = true;
        } else if (std.mem.eql(u8, raw_args[i], "--init")) {
            want_init = true;
        } else if (std.mem.eql(u8, raw_args[i], "--strict")) {
            want_strict = true;
        } else if (std.mem.eql(u8, raw_args[i], "--json-errors")) {
            want_json_errors = true;
        } else if (std.mem.eql(u8, raw_args[i], "--verbose-passes")) {
            want_verbose_passes = true;
        } else if (std.mem.eql(u8, raw_args[i], "--summary")) {
            want_summary = true;
        } else if (std.mem.eql(u8, raw_args[i], "--config")) {
            if (i + 1 < raw_args.len) {
                config_path = raw_args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--color")) {
            if (i + 1 < raw_args.len) {
                const val = raw_args[i + 1];
                if (std.mem.eql(u8, val, "always")) {
                    want_color = .always;
                } else if (std.mem.eql(u8, val, "never")) {
                    want_color = .never;
                } else if (!std.mem.eql(u8, val, "auto")) {
                    return error.UnknownFlag;
                }
                i += 1;
            } else {
                want_color = .always;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--import-path")) {
            if (i + 1 < raw_args.len) {
                try import_paths.append(alloc, raw_args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--output") or std.mem.eql(u8, raw_args[i], "-o")) {
            // Output flag: append to filtered args, handled by parseOutputFlag below
            try filtered.append(alloc, raw_args[i]);
            if (i + 1 < raw_args.len) {
                i += 1;
                try filtered.append(alloc, raw_args[i]);
            }
        } else {
            // Reject unrecognized long flags (--something)
            if (raw_args[i].len > 2 and raw_args[i][0] == '-' and raw_args[i][1] == '-' and !isKnownLongFlag(raw_args[i])) {
                return error.UnknownFlag;
            }
            try filtered.append(alloc, raw_args[i]);
        }
    }
    const fargs = try filtered.toOwnedSlice(alloc);
    const import_path_list = try import_paths.toOwnedSlice(alloc);

    if (want_version) {
        return .{ .dialect = dialect, .target = target, .command = .version, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
    }

    const flags = GlobalFlags{
        .stats = want_stats,
        .check = want_check,
        .dry_run = want_dry_run,
        .strict = want_strict,
        .verbose_passes = want_verbose_passes,
        .json_errors = want_json_errors,
        .color = want_color,
        .format = diff_format,
        .validate_only = want_validate_only,
        .quiet = want_quiet,
        .import_paths = import_path_list,
        .summary = want_summary,
        .config_path = config_path,
    };

    // No positional args, or first arg is a flag → default compile from stdin
    if (fargs.len < 1 or (fargs.len > 0 and fargs[0][0] == '-')) {
        // Check for --help before treating as stdin compile
        if (hasHelpFlag(fargs)) {
            return .{ .dialect = dialect, .target = target, .command = .{ .help = .{} }, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
        }
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
            .color = want_color,
            .init_flag = want_init,
            .config_path = config_path,
        };
    }

    const sub = fargs[0];

    // Check for subcommand help: `rune <cmd> --help` or `rune <cmd> -h`
    if (hasHelpFlag(fargs)) {
        return .{ .dialect = dialect, .target = target, .command = .{ .help = .{ .subcommand = sub } }, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
    }

    // Table-driven subcommand dispatch.
    const SubcommandParser = *const fn ([]const []const u8, dialect_enum.Dialect, Target, GlobalFlags) anyerror!ParsedArgs;
    const parsers = [_]struct { name: []const u8, parse: SubcommandParser }{
        .{ .name = "diff", .parse = parseDiffArgs },
        .{ .name = "migrate", .parse = parseMigrateArgs },
        .{ .name = "reverse", .parse = parseReverseArgs },
        .{ .name = "generate", .parse = parseGenerateArgs },
        .{ .name = "validate", .parse = parseValidateArgs },
        .{ .name = "check", .parse = parseCheckArgs },
        .{ .name = "stats", .parse = parseStatsArgs },
        .{ .name = "docs", .parse = parseDocsArgs },
        .{ .name = "format", .parse = parseFormatArgs },
        .{ .name = "init", .parse = parseInitArgs },
        .{ .name = "completions", .parse = parseCompletionsArgs },
    };
    for (parsers) |entry| {
        if (std.mem.eql(u8, sub, entry.name)) {
            return entry.parse(fargs, dialect, target, flags);
        }
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
        .color = want_color,
        .init_flag = want_init,
        .config_path = config_path,
    };
}

pub fn parseDialect(s: []const u8) !dialect_enum.Dialect {
    if (std.mem.eql(u8, s, "mysql")) return .mysql;
    if (std.mem.eql(u8, s, "pg") or std.mem.eql(u8, s, "postgres")) return .pg;
    if (std.mem.eql(u8, s, "sqlite") or std.mem.eql(u8, s, "sq")) return .sqlite;
    if (std.mem.eql(u8, s, "mssql") or std.mem.eql(u8, s, "sqlserver")) return .mssql;
    if (std.mem.eql(u8, s, "oracle") or std.mem.eql(u8, s, "ora")) return .oracle;
    if (std.mem.eql(u8, s, "db2") or std.mem.eql(u8, s, "idb2")) return .db2;
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

pub const CommandInfo = struct {
    name: []const u8,
    args: []const u8, // argument syntax (e.g. "<old.ss> <new.ss>")
    description: []const u8,
};

pub const COMMAND_REGISTRY = [_]CommandInfo{
    .{ .name = "validate", .args = "[input.ss]", .description = "Validate .ss schema (no output)" },
    .{ .name = "check", .args = "[input.ss]", .description = "Check schema validity (exit 1 on error)" },
    .{ .name = "stats", .args = "[input.ss]", .description = "Print schema statistics (table/field/view counts)" },
    .{ .name = "diff", .args = "<old.ss> <new.ss>", .description = "Show schema differences" },
    .{ .name = "migrate", .args = "<old.ss> <new.ss> [--name <label>] [--dir <path>] [--incremental]", .description = "Generate ALTER TABLE migration SQL" },
    .{ .name = "reverse", .args = "[input.sql]", .description = "Reverse SQL DDL to .ss schema" },
    .{ .name = "docs", .args = "[input.ss]", .description = "Generate Markdown documentation" },
    .{ .name = "format", .args = "[input.ss]", .description = "Auto-format .ss schema file" },
    .{ .name = "generate", .args = "<generator> [input.ss]", .description = "Generate output in specified format" },
    .{ .name = "init", .args = "[name]", .description = "Create a starter .ss schema file" },
    .{ .name = "completions", .args = "<shell>", .description = "Generate shell completions (bash|zsh|fish|powershell)" },
};

/// Known long flags for edit-distance suggestions.
pub const KNOWN_FLAGS = [_][]const u8{
    "--version",        "--help",        "--stats",  "--quiet",         "--check",  "--dry-run",
    "--dialect",        "--target",      "--format", "--validate-only", "--strict", "--json-errors",
    "--verbose-passes", "--import-path", "--trace",  "--rollback",      "--output", "--list",
    "--name",           "--dir",         "--incremental",               "--color",  "--init",
    "--summary",        "--config",      "--template",
};

/// Find the most similar known flag using edit distance. Returns null if best match > 3.
pub fn suggestSimilarFlag(unknown: []const u8) ?[]const u8 {
    const edit = @import("utils/edit_distance.zig");
    var best_name: ?[]const u8 = null;
    var best_dist: usize = 4; // threshold: ≤3 edits
    inline for (KNOWN_FLAGS) |known| {
        const d = edit.runtimeEditDistance(unknown, known);
        if (d < best_dist) {
            best_dist = d;
            best_name = known;
        }
    }
    return best_name;
}

/// Check if a long flag (--flag) is recognized by the parser.
fn isKnownLongFlag(flag: []const u8) bool {
    inline for (KNOWN_FLAGS) |k| {
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

/// Check if a generator name is valid (matches an entry in the generator registry).
fn isValidGeneratorName(name: []const u8) bool {
    const generator = @import("generator.zig");
    for (generator.REGISTRY) |gen| {
        if (std.mem.eql(u8, gen.name, name)) return true;
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
            .summary = opts.summary,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

fn parseMigrateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    // Handle `rune migrate status [--dir <path>]`
    if (fargs.len >= 2 and std.mem.eql(u8, fargs[1], "status")) {
        var status_dir: ?[]const u8 = null;
        var j: usize = 2;
        while (j < fargs.len) : (j += 1) {
            if (std.mem.eql(u8, fargs[j], "--dir") and j + 1 < fargs.len) {
                status_dir = fargs[j + 1];
                j += 1;
            }
        }
        return .{
            .dialect = dialect,
            .target = target,
            .command = .{ .migrate_status = .{ .dir = status_dir, .json_errors = opts.json_errors } },
            .quiet = opts.quiet,
            .strict = opts.strict,
            .json_errors = opts.json_errors,
            .import_paths = opts.import_paths,
            .color = opts.color,
            .config_path = opts.config_path,
        };
    }
    if (fargs.len < 3) return error.MigrateMissingArgs;
    var name: ?[]const u8 = null;
    var dir: ?[]const u8 = null;
    var incremental = false;
    var j: usize = 3;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--name") and j + 1 < fargs.len) {
            name = fargs[j + 1];
            j += 1;
        } else if (std.mem.eql(u8, fargs[j], "--dir") and j + 1 < fargs.len) {
            dir = fargs[j + 1];
            j += 1;
        } else if (std.mem.eql(u8, fargs[j], "--incremental")) {
            incremental = true;
        }
    }
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
            .name = name,
            .dir = dir,
            .incremental = incremental,
            .summary = opts.summary,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
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
            .format = opts.format,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
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
    // Early validation: reject unknown generator names before hitting the pipeline
    if (generator) |gen_name| {
        if (gen_name.len > 0 and !isValidGeneratorName(gen_name)) {
            return error.UnknownGenerator;
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
        .color = opts.color,
        .config_path = opts.config_path,
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
    color: ColorMode,
    format: DiffFormat,
    validate_only: bool,
    quiet: bool,
    import_paths: []const []const u8,
    summary: bool = false,
    config_path: ?[]const u8 = null,
};

fn parseSimpleSubcommand(dialect: dialect_enum.Dialect, target: Target, cmd: Command, opts: GlobalFlags) ParsedArgs {
    return .{
        .dialect = dialect,
        .target = target,
        .command = cmd,
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

fn parseSimpleInputArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags, cmd: Command) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    // Inject input into the command variant
    const final_cmd: Command = switch (cmd) {
        .validate => |c| .{ .validate = .{ .input = input orelse c.input, .stats = c.stats, .verbose_passes = c.verbose_passes } },
        .check => |c| .{ .check = .{ .input = input orelse c.input, .stats = c.stats, .verbose_passes = c.verbose_passes } },
        .stats => |c| .{ .stats = .{ .input = input orelse c.input, .format = c.format } },
        else => cmd,
    };
    return parseSimpleSubcommand(dialect, target, final_cmd, opts);
}

fn parseValidateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    return parseSimpleInputArgs(fargs, dialect, target, opts, .{ .validate = .{ .input = null, .stats = opts.stats, .verbose_passes = opts.verbose_passes } });
}

fn parseCheckArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    return parseSimpleInputArgs(fargs, dialect, target, opts, .{ .check = .{ .input = null, .stats = opts.stats, .verbose_passes = opts.verbose_passes } });
}

fn parseStatsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    const stats_format: StatsFormat = if (opts.format == .json) .json else .text;
    return parseSimpleSubcommand(dialect, target, .{ .stats = .{ .input = input, .format = stats_format } }, opts);
}

fn parseDocsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .docs = .{ .input = input, .output = parseOutputFlag(fargs, 1) } }, opts);
}

fn parseFormatArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .format_cmd = .{ .input = input, .output = parseOutputFlag(fargs, 1) } }, opts);
}

fn parseInitArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const name = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .init = .{ .name = name, .output = parseOutputFlag(fargs, 1) } }, opts);
}

fn parseCompletionsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const shell = if (fargs.len > 1) fargs[1] else "bash";
    return parseSimpleSubcommand(dialect, target, .{ .completions = .{ .shell = shell } }, opts);
}

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
    std.debug.print("  --init          Create a starter schema file (equivalent to 'rune init')\n", .{});
    std.debug.print("  --config        Path to project config file (default: ./rune.toml)\n", .{});
    std.debug.print("  -v, --version   Print version and exit\n", .{});
    std.debug.print("  -h, --help      Show this help message and exit\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  rune schema.ss                       # Compile to MySQL DDL\n", .{});
    std.debug.print("  rune schema.ss -d pg                 # Compile to PostgreSQL\n", .{});
    std.debug.print("  rune schema.ss -d oracle             # Compile to Oracle\n", .{});
    std.debug.print("  rune validate schema.ss              # Validate schema (no output)\n", .{});
    std.debug.print("  rune validate schema.ss -s           # Validate with stats\n", .{});
    std.debug.print("  rune --stats schema.ss               # Show compilation stats\n", .{});
    std.debug.print("  rune stats schema.ss --format json   # Stats as JSON\n", .{});
    std.debug.print("  rune --check schema.ss               # Validate without output\n", .{});
    std.debug.print("  rune diff old.ss new.ss              # Show schema differences\n", .{});
    std.debug.print("  rune diff old.ss new.ss --format json # Diff as JSON\n", .{});
    std.debug.print("  rune migrate old.ss new.ss -o m.sql  # Generate migration SQL\n", .{});
    std.debug.print("  rune migrate old.ss new.ss --rollback # Generate rollback SQL\n", .{});
    std.debug.print("  rune reverse schema.sql -T           # Reverse-engineer with templates\n", .{});
    std.debug.print("  rune generate json-schema schema.ss  # Generate JSON Schema from .ss\n", .{});
    std.debug.print("  rune generate --list                 # Show available generators\n", .{});
    std.debug.print("  rune init myapp                      # Create starter schema\n", .{});
    std.debug.print("  rune fmt schema.ss                   # Auto-format schema\n", .{});
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
            // Show command-specific options
            if (std.mem.eql(u8, subcommand, "diff") or std.mem.eql(u8, subcommand, "migrate")) {
                std.debug.print("\nOptions:\n", .{});
                std.debug.print("  --format        Output format: text (default), json, sarif, markdown\n", .{});
                std.debug.print("  -t, --trace     Print intermediate pipeline stages\n", .{});
                std.debug.print("  -s, --stats     Print compilation statistics\n", .{});
                std.debug.print("  --check         Exit 1 if there are differences\n", .{});
                if (std.mem.eql(u8, subcommand, "migrate")) {
                    std.debug.print("  --rollback      Generate rollback SQL instead\n", .{});
                    std.debug.print("  --dry-run       Show SQL without writing to file\n", .{});
                    std.debug.print("  --summary       Show summary only (no full SQL)\n", .{});
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
            } else if (std.mem.eql(u8, subcommand, "completions")) {
                std.debug.print("\nArguments:\n", .{});
                std.debug.print("  shell           Target shell: bash (default), zsh, fish, powershell\n", .{});
            } else {
                std.debug.print("\nGlobal options also apply: -d/--dialect, -s/--stats, -q/--quiet, -h/--help\n", .{});
            }
            return;
        }
    }
    std.debug.print("\nUnknown command: {s}\n", .{subcommand});
}
