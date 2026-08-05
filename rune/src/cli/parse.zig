const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const types = @import("types.zig");

const Target = types.Target;
const DiffFormat = types.DiffFormat;
const StatsFormat = types.StatsFormat;
const Command = types.Command;
const ParsedArgs = types.ParsedArgs;
const ColorMode = types.ColorMode;
const GlobalFlags = types.GlobalFlags;
const COMMAND_REGISTRY = types.COMMAND_REGISTRY;
const KNOWN_FLAGS = types.KNOWN_FLAGS;

// ─── Re-exports from sub-modules ────────────────────────────────

pub const parse_compile = @import("parse_compile.zig");
pub const parse_utils = @import("parse_utils.zig");

// ─── Shared Flag Parsers ───────────────────────────────────────

pub fn parseRollbackFlag(args: []const []const u8, start: usize) bool {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "--rollback")) {
            return true;
        }
    }
    return false;
}

pub fn parseOutputFlag(args: []const []const u8, start: usize) ?[]const u8 {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if ((std.mem.eql(u8, args[j], "-o") or std.mem.eql(u8, args[j], "--output")) and j + 1 < args.len) {
            const val = args[j + 1];
            if (val.len > 0 and val[0] == '-') return null;
            return val;
        }
    }
    return null;
}

pub fn parseTraceFlag(args: []const []const u8, start: usize) bool {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "-t") or std.mem.eql(u8, args[j], "--trace")) {
            return true;
        }
    }
    return false;
}

pub fn hasHelpFlag(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) return true;
    }
    return false;
}

// ─── Unknown Flag / Command Detection ─────────────────────────

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

pub fn suggestSimilarFlag(unknown: []const u8) ?[]const u8 {
    const edit = @import("../utils/edit_distance.zig");
    var best_name: ?[]const u8 = null;
    var best_dist: usize = 4;
    inline for (KNOWN_FLAGS) |known| {
        const d = edit.runtimeEditDistance(unknown, known);
        if (d < best_dist) {
            best_dist = d;
            best_name = known;
        }
    }
    return best_name;
}

pub fn isKnownLongFlag(flag: []const u8) bool {
    inline for (KNOWN_FLAGS) |k| {
        if (std.mem.eql(u8, flag, k)) return true;
    }
    return false;
}

fn isKnownCommand(name: []const u8) bool {
    for (COMMAND_REGISTRY) |cmd| {
        if (std.mem.eql(u8, name, cmd.name)) return true;
    }
    return false;
}

pub fn isValidGeneratorName(name: []const u8) bool {
    const generator = @import("../generator.zig");
    for (generator.REGISTRY) |gen| {
        if (std.mem.eql(u8, gen.name, name)) return true;
    }
    return false;
}

pub const parseDialect = dialect_enum.parseDialect;

fn parseTarget(s: []const u8) !Target {
    if (std.mem.eql(u8, s, "sql")) return .sql;
    if (std.mem.eql(u8, s, "json-schema") or std.mem.eql(u8, s, "json_schema")) return .json_schema;
    return error.UnknownTarget;
}

// ─── Argument Parsing ──────────────────────────────────────────

pub fn parseArgs(alloc: std.mem.Allocator, raw_args: []const []const u8) !ParsedArgs {
    var dialect: dialect_enum.Dialect = .mysql;
    var dialect_was_explicit = false;
    var target: Target = .sql;
    var filtered = try std.ArrayList([]const u8).initCapacity(alloc, raw_args.len);

    var i: usize = 1;
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
    var want_stream = false;
    var want_parallel = false;
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
                dialect = dialect_enum.parseDialect(raw_args[i + 1]) catch |e| {
                    if (e == error.UnknownDialect) return error.UnknownDialect;
                    return error.MissingDialectValue;
                };
                dialect_was_explicit = true;
                i += 1;
            } else {
                return error.MissingDialectValue;
            }
        } else if (std.mem.eql(u8, raw_args[i], "--target")) {
            if (i + 1 < raw_args.len) {
                target = parseTarget(raw_args[i + 1]) catch |e| {
                    if (e == error.UnknownTarget) return error.UnknownTarget;
                    return error.MissingTargetValue;
                };
                i += 1;
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
        } else if (std.mem.eql(u8, raw_args[i], "--stream")) {
            want_stream = true;
        } else if (std.mem.eql(u8, raw_args[i], "--parallel")) {
            want_parallel = true;
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
            try filtered.append(alloc, raw_args[i]);
            if (i + 1 < raw_args.len) {
                i += 1;
                try filtered.append(alloc, raw_args[i]);
            }
        } else {
            if (raw_args[i].len > 2 and raw_args[i][0] == '-' and raw_args[i][1] == '-' and !isKnownLongFlag(raw_args[i])) {
                return error.UnknownFlag;
            }
            try filtered.append(alloc, raw_args[i]);
        }
    }
    const fargs = try filtered.toOwnedSlice(alloc);
    const import_path_list = try import_paths.toOwnedSlice(alloc);

    if (want_version) {
        return .{ .dialect = dialect, .dialect_was_explicit = dialect_was_explicit, .target = target, .command = .version, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
    }

    const flags = GlobalFlags{
        .dialect_was_explicit = dialect_was_explicit,
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

    if (fargs.len < 1 or (fargs.len > 0 and fargs[0][0] == '-')) {
        if (hasHelpFlag(fargs)) {
            return .{ .dialect = dialect, .dialect_was_explicit = dialect_was_explicit, .target = target, .command = .{ .help = .{} }, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
        }
        return .{
            .dialect = dialect,
            .dialect_was_explicit = dialect_was_explicit,
            .target = target,
            .command = .{ .compile = .{
                .input = null,
                .output = parseOutputFlag(fargs, 0),
                .trace = parseTraceFlag(fargs, 0),
                .stats = want_stats,
                .check = want_check,
                .verbose_passes = want_verbose_passes,
                .stream = want_stream,
                .parallel = want_parallel,
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

    if (hasHelpFlag(fargs)) {
        return .{ .dialect = dialect, .dialect_was_explicit = dialect_was_explicit, .target = target, .command = .{ .help = .{ .subcommand = sub } }, .quiet = want_quiet, .strict = want_strict, .json_errors = want_json_errors, .import_paths = import_path_list, .color = want_color, .init_flag = want_init, .config_path = config_path };
    }

    const SubcommandParser = *const fn ([]const []const u8, dialect_enum.Dialect, Target, GlobalFlags) anyerror!ParsedArgs;
    const parsers = [_]struct { name: []const u8, parse: SubcommandParser }{
        .{ .name = "diff", .parse = parse_compile.parseDiffArgs },
        .{ .name = "migrate", .parse = parse_compile.parseMigrateArgs },
        .{ .name = "reverse", .parse = parse_compile.parseReverseArgs },
        .{ .name = "generate", .parse = parse_compile.parseGenerateArgs },
        .{ .name = "validate", .parse = parse_compile.parseValidateArgs },
        .{ .name = "check", .parse = parse_compile.parseCheckArgs },
        .{ .name = "stats", .parse = parse_compile.parseStatsArgs },
        .{ .name = "docs", .parse = parse_utils.parseDocsArgs },
        .{ .name = "format", .parse = parse_utils.parseFormatArgs },
        .{ .name = "init", .parse = parse_utils.parseInitArgs },
        .{ .name = "completions", .parse = parse_utils.parseCompletionsArgs },
        .{ .name = "hooks", .parse = parse_utils.parseHooksArgs },
        .{ .name = "watch", .parse = parse_utils.parseWatchArgs },
    };
    for (parsers) |entry| {
        if (std.mem.eql(u8, sub, entry.name)) {
            return entry.parse(fargs, dialect, target, flags);
        }
    }

    if (fargs.len > 0 and std.mem.indexOfScalar(u8, fargs[0], '.') == null) {
        if (!isKnownCommand(fargs[0]) and !std.mem.eql(u8, fargs[0], "-")) {
            return error.UnknownCommand;
        }
    }

    const input = if (fargs.len > 0) fargs[0] else null;
    return .{
        .dialect = dialect,
        .dialect_was_explicit = dialect_was_explicit,
        .target = target,
        .command = .{ .compile = .{
            .input = input,
            .output = parseOutputFlag(fargs, 1),
            .trace = parseTraceFlag(fargs, 1),
            .stats = want_stats,
            .check = want_check,
            .verbose_passes = want_verbose_passes,
            .stream = want_stream,
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
