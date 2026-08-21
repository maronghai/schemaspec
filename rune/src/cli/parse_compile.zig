const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const types = @import("types.zig");
const shared = @import("parse.zig");

const Target = types.Target;
const DiffFormat = types.DiffFormat;
const StatsFormat = types.StatsFormat;
const Command = types.Command;
const ParsedArgs = types.ParsedArgs;
const GlobalFlags = types.GlobalFlags;

// ─── Helpers ────────────────────────────────────────────────────

fn parseSimpleInputArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags, cmd: Command) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    const final_cmd: Command = switch (cmd) {
        .validate => |c| .{ .validate = .{ .input = input orelse c.input, .stats = c.stats, .verbose_passes = c.verbose_passes, .format = switch (opts.format) {
            .json => .json,
            .sarif => .sarif,
            else => .text,
        }, .per_table = c.per_table, .fix = c.fix } },
        .check => |c| .{ .check = .{ .input = input orelse c.input, .stats = c.stats, .verbose_passes = c.verbose_passes, .format = if (opts.format == .json) .json else .text } },
        .stats => |c| .{ .stats = .{ .input = input orelse c.input, .format = c.format } },
        else => cmd,
    };
    return shared.parseSimpleSubcommand(dialect, target, final_cmd, opts);
}

// ─── Subcommand Parsers ────────────────────────────────────────

pub fn parseDiffArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    if (fargs.len < 3) return error.DiffMissingArgs;
    var from_sql: ?[]const u8 = null;
    var j: usize = 3;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--from-sql") and j + 1 < fargs.len) {
            from_sql = fargs[j + 1];
            j += 1;
        }
    }
    return .{
        .dialect = dialect,
        .dialect_was_explicit = opts.dialect_was_explicit,
        .target = target,
        .command = .{ .diff = .{
            .old = fargs[1],
            .new = fargs[2],
            .trace = shared.parseTraceFlag(fargs, 3),
            .stats = opts.stats,
            .format = opts.format,
            .check = opts.check,
            .summary = opts.summary,
            .from_sql = from_sql,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

pub fn parseMigrateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
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
            .dialect_was_explicit = opts.dialect_was_explicit,
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
    var graph = false;
    var no_lint = false;
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
        } else if (std.mem.eql(u8, fargs[j], "--graph")) {
            graph = true;
        } else if (std.mem.eql(u8, fargs[j], "--no-lint")) {
            no_lint = true;
        }
    }
    return .{
        .dialect = dialect,
        .dialect_was_explicit = opts.dialect_was_explicit,
        .target = target,
        .command = .{ .migrate = .{
            .old = fargs[1],
            .new = fargs[2],
            .output = shared.parseOutputFlag(fargs, 3),
            .trace = shared.parseTraceFlag(fargs, 3),
            .rollback = shared.parseRollbackFlag(fargs, 3),
            .stats = opts.stats,
            .dry_run = opts.dry_run,
            .format = opts.format,
            .check = opts.check,
            .name = name,
            .dir = dir,
            .incremental = incremental,
            .summary = opts.summary,
            .graph = graph,
            .no_lint = no_lint,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

pub fn parseReverseArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
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
        .dialect_was_explicit = opts.dialect_was_explicit,
        .target = target,
        .command = .{ .reverse = .{
            .input = input,
            .output = shared.parseOutputFlag(fargs, 1),
            .with_templates = with_templates,
            .trace = shared.parseTraceFlag(fargs, 1),
            .stats = opts.stats,
            .validate_only = opts.validate_only,
            .format = opts.format,
            .check = opts.check,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

pub fn parseGenerateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) !ParsedArgs {
    var want_list = false;
    var want_dry_run = false;
    var want_check = false;
    var generators_str: ?[]const u8 = null;
    var template_dir: ?[]const u8 = null;

    // First pass: scan for flags
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--list") or std.mem.eql(u8, fargs[j], "-l")) {
            want_list = true;
        } else if (std.mem.eql(u8, fargs[j], "--dry-run")) {
            want_dry_run = true;
        } else if (std.mem.eql(u8, fargs[j], "--check")) {
            want_check = true;
        } else if (std.mem.eql(u8, fargs[j], "--generators") and j + 1 < fargs.len) {
            j += 1;
            generators_str = fargs[j];
        } else if (std.mem.eql(u8, fargs[j], "--template-dir") and j + 1 < fargs.len) {
            j += 1;
            template_dir = fargs[j];
        }
    }

    // Second pass: process positional arguments
    var generator: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    j = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--list") or std.mem.eql(u8, fargs[j], "-l") or
            std.mem.eql(u8, fargs[j], "--generators") or std.mem.eql(u8, fargs[j], "--dry-run") or
            std.mem.eql(u8, fargs[j], "--check") or std.mem.eql(u8, fargs[j], "--template-dir"))
        {
            // Skip flags and their values
            if (std.mem.eql(u8, fargs[j], "--generators") or std.mem.eql(u8, fargs[j], "--template-dir")) j += 1;
            continue;
        }
        if (generator == null and generators_str == null) {
            generator = fargs[j];
        } else if (input == null) {
            input = fargs[j];
        }
    }

    if (generator) |gen_name| {
        if (gen_name.len > 0 and !shared.isValidGeneratorName(gen_name)) {
            return error.UnknownGenerator;
        }
    }
    return .{
        .dialect = dialect,
        .dialect_was_explicit = opts.dialect_was_explicit,
        .target = target,
        .command = .{ .generate = .{
            .generator = generator orelse "",
            .generators_str = generators_str,
            .input = input,
            .output = shared.parseOutputFlag(fargs, 1),
            .list = want_list,
            .check = want_check,
            .dry_run = want_dry_run,
            .template_dir = template_dir,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

pub fn parseValidateArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    // Scan for --per-table and --fix flags
    var per_table = false;
    var fix = false;
    for (fargs[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--per-table")) {
            per_table = true;
        } else if (std.mem.eql(u8, arg, "--fix")) {
            fix = true;
        }
    }
    return parseSimpleInputArgs(fargs, dialect, target, opts, .{ .validate = .{ .input = null, .stats = opts.stats, .verbose_passes = opts.verbose_passes, .per_table = per_table, .fix = fix } });
}

pub fn parseCheckArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    return parseSimpleInputArgs(fargs, dialect, target, opts, .{ .check = .{ .input = null, .stats = opts.stats, .verbose_passes = opts.verbose_passes } });
}

pub fn parseStatsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    const stats_format: StatsFormat = if (opts.summary)
        .summary
    else if (opts.format == .json)
        .json
    else if (opts.format == .markdown)
        .markdown
    else
        .text;
    // Scan for --per-table, --audit, and --min-score flags
    var per_table = false;
    var audit = false;
    var min_score: ?u8 = null;
    for (fargs[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--per-table")) {
            per_table = true;
        }
        if (std.mem.eql(u8, arg, "--audit")) {
            audit = true;
        }
        // Parse --min-score N
        if (std.mem.startsWith(u8, arg, "--min-score=")) {
            const val = arg["--min-score=".len..];
            min_score = std.fmt.parseInt(u8, val, 10) catch null;
        }
        if (std.mem.eql(u8, arg, "--min-score")) {
            // Next arg is the value
            // We'll handle this in the loop by checking a flag
        }
    }
    // Handle --min-score as separate arg (--min-score 80)
    for (fargs[1..], 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--min-score") and i + 1 < fargs.len - 1) {
            min_score = std.fmt.parseInt(u8, fargs[i + 2], 10) catch null;
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .stats = .{ .input = input, .format = stats_format, .per_table = per_table, .audit = audit, .min_score = min_score } }, opts);
}
