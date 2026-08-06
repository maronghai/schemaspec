const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const types = @import("types.zig");
const shared = @import("parse.zig");

const Target = types.Target;
const Command = types.Command;
const ParsedArgs = types.ParsedArgs;
const GlobalFlags = types.GlobalFlags;

// ─── Helpers ────────────────────────────────────────────────────

fn parseSimpleSubcommand(dialect: dialect_enum.Dialect, target: Target, cmd: Command, opts: GlobalFlags) ParsedArgs {
    return .{
        .dialect = dialect,
        .dialect_was_explicit = opts.dialect_was_explicit,
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

// ─── Subcommand Parsers ────────────────────────────────────────

pub fn parseDocsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .docs = .{ .input = input, .output = shared.parseOutputFlag(fargs, 1) } }, opts);
}

pub fn parseFormatArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .format_cmd = .{ .input = input, .output = shared.parseOutputFlag(fargs, 1) } }, opts);
}

pub fn parseInitArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const name = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .init = .{ .name = name, .output = shared.parseOutputFlag(fargs, 1) } }, opts);
}

pub fn parseCompletionsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const shell = if (fargs.len > 1) fargs[1] else "bash";
    return parseSimpleSubcommand(dialect, target, .{ .completions = .{ .shell = shell } }, opts);
}

pub fn parseHooksArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const hook_type = if (fargs.len > 1) fargs[1] else "pre-commit";
    return parseSimpleSubcommand(dialect, target, .{ .hooks = .{ .hook_type = hook_type } }, opts);
}

pub fn parseLintArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    return parseSimpleSubcommand(dialect, target, .{ .lint = .{
        .input = input,
        .json_errors = opts.json_errors,
        .strict = opts.strict,
    } }, opts);
}

pub fn parseWatchArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    if (fargs.len < 2) return error.MissingArgs;
    var interval_ms: u64 = 1000;
    var parallel = false;
    var trace = false;
    var stats = false;
    var json_errors = false;
    var j: usize = 2;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--interval") and j + 1 < fargs.len) {
            interval_ms = std.fmt.parseInt(u64, fargs[j + 1], 10) catch 1000;
            j += 1;
        } else if (std.mem.eql(u8, fargs[j], "--parallel")) {
            parallel = true;
        } else if (std.mem.eql(u8, fargs[j], "--trace") or std.mem.eql(u8, fargs[j], "-t")) {
            trace = true;
        } else if (std.mem.eql(u8, fargs[j], "--stats") or std.mem.eql(u8, fargs[j], "-s")) {
            stats = true;
        } else if (std.mem.eql(u8, fargs[j], "--json-errors")) {
            json_errors = true;
        }
    }
    return .{
        .dialect = dialect,
        .dialect_was_explicit = opts.dialect_was_explicit,
        .target = target,
        .command = .{ .watch = .{
            .input = fargs[1],
            .interval_ms = interval_ms,
            .output = shared.parseOutputFlag(fargs, 2),
            .parallel = parallel,
            .trace = trace,
            .stats = stats,
            .json_errors = json_errors,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = json_errors or opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}
