const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const types = @import("types.zig");
const shared = @import("parse.zig");

const Target = types.Target;
const Command = types.Command;
const ParsedArgs = types.ParsedArgs;
const GlobalFlags = types.GlobalFlags;

// ─── Subcommand Parsers ────────────────────────────────────────

pub fn parseDocsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    // Map global --format flag to docs format
    const doc_format: types.DocsFormat = switch (opts.format) {
        .json => .json,
        else => .markdown,
    };
    return shared.parseSimpleSubcommand(dialect, target, .{ .docs = .{ .input = input, .output = shared.parseOutputFlag(fargs, 1), .doc_format = doc_format } }, opts);
}

pub fn parseExportArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    // Map global --format flag to export format
    const export_format: types.ExportFormat = switch (opts.format) {
        .json => .json,
        .sarif => .markdown,
        else => .text,
    };
    return shared.parseSimpleSubcommand(dialect, target, .{ .export_cmd = .{ .input = input, .output = shared.parseOutputFlag(fargs, 1), .format = export_format } }, opts);
}

pub fn parseFormatArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    var diff = false;
    var write = false;
    var format_dialect: ?dialect_enum.Dialect = null;
    for (fargs[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--diff")) {
            diff = true;
        } else if (std.mem.eql(u8, arg, "--write")) {
            write = true;
        }
    }
    // Parse --dialect/-d with value
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if ((std.mem.eql(u8, fargs[j], "--dialect") or std.mem.eql(u8, fargs[j], "-d")) and j + 1 < fargs.len) {
            format_dialect = try dialect_enum.parseDialect(fargs[j + 1]);
            j += 1;
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .format_cmd = .{ .input = input, .output = shared.parseOutputFlag(fargs, 1), .check = opts.check, .diff = diff, .write = write, .dialect = format_dialect } }, opts);
}

pub fn parseInitArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    var name: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var template: ?[]const u8 = null;
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--output-dir") and j + 1 < fargs.len) {
            j += 1;
            output_dir = fargs[j];
        } else if (std.mem.eql(u8, fargs[j], "--template") and j + 1 < fargs.len) {
            j += 1;
            template = fargs[j];
        } else if (std.mem.eql(u8, fargs[j], "-o") and j + 1 < fargs.len) {
            j += 1;
            output = fargs[j];
        } else if (fargs[j][0] != '-') {
            name = fargs[j];
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .init = .{ .name = name, .output = output, .output_dir = output_dir, .template = template } }, opts);
}

pub fn parseCompletionsArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const shell = if (fargs.len > 1) fargs[1] else "bash";
    return shared.parseSimpleSubcommand(dialect, target, .{ .completions = .{ .shell = shell } }, opts);
}

pub fn parseHooksArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const hook_type = if (fargs.len > 1) fargs[1] else "pre-commit";
    return shared.parseSimpleSubcommand(dialect, target, .{ .hooks = .{ .hook_type = hook_type } }, opts);
}

pub fn parseLintArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    var input: ?[]const u8 = null;
    var input2: ?[]const u8 = null;
    var json_errors = opts.json_errors;
    var strict = opts.strict;
    var format: types.LintFormat = .text;
    var rules: ?[]const u8 = null;
    var fix = false;
    var dry_run = opts.dry_run;
    var show_rules = false;
    var init_config = false;
    var include_views = false;
    var summary = false;
    var positional_count: usize = 0;
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--json-errors")) {
            json_errors = true;
        } else if (std.mem.eql(u8, fargs[j], "--strict")) {
            strict = true;
        } else if (std.mem.eql(u8, fargs[j], "--fix")) {
            fix = true;
        } else if (std.mem.eql(u8, fargs[j], "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, fargs[j], "--show-rules")) {
            show_rules = true;
        } else if (std.mem.eql(u8, fargs[j], "--init")) {
            init_config = true;
        } else if (std.mem.eql(u8, fargs[j], "--include-views")) {
            include_views = true;
        } else if (std.mem.eql(u8, fargs[j], "--summary")) {
            summary = true;
        } else if (std.mem.eql(u8, fargs[j], "--format") and j + 1 < fargs.len) {
            j += 1;
            if (std.mem.eql(u8, fargs[j], "sarif")) {
                format = .sarif;
            } else if (std.mem.eql(u8, fargs[j], "json")) {
                format = .json;
            } else {
                format = .text;
            }
        } else if (std.mem.eql(u8, fargs[j], "--rules") and j + 1 < fargs.len) {
            j += 1;
            rules = fargs[j];
        } else if (fargs[j][0] != '-') {
            positional_count += 1;
            if (positional_count == 1) input = fargs[j];
            if (positional_count == 2) input2 = fargs[j];
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .lint = .{
        .input = input,
        .input2 = input2,
        .json_errors = json_errors,
        .strict = strict,
        .format = format,
        .rules = rules,
        .fix = fix,
        .dry_run = dry_run,
        .show_rules = show_rules,
        .init_config = init_config,
        .include_views = include_views,
        .summary = summary,
    } }, opts);
}

pub fn parseWatchArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    if (fargs.len < 2) return error.MissingArgs;
    var interval_ms: u64 = 1000;
    var stream = false;
    var parallel = false;
    var trace = false;
    var stats = false;
    var json_errors = false;
    var recursive = false;
    var j: usize = 2;
    while (j < fargs.len) : (j += 1) {
        if (std.mem.eql(u8, fargs[j], "--interval") and j + 1 < fargs.len) {
            interval_ms = std.fmt.parseInt(u64, fargs[j + 1], 10) catch 1000;
            j += 1;
        } else if (std.mem.eql(u8, fargs[j], "--stream")) {
            stream = true;
        } else if (std.mem.eql(u8, fargs[j], "--parallel")) {
            parallel = true;
        } else if (std.mem.eql(u8, fargs[j], "--trace") or std.mem.eql(u8, fargs[j], "-t")) {
            trace = true;
        } else if (std.mem.eql(u8, fargs[j], "--stats") or std.mem.eql(u8, fargs[j], "-s")) {
            stats = true;
        } else if (std.mem.eql(u8, fargs[j], "--json-errors")) {
            json_errors = true;
        } else if (std.mem.eql(u8, fargs[j], "--recursive")) {
            recursive = true;
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
            .stream = stream,
            .parallel = parallel,
            .trace = trace,
            .stats = stats,
            .json_errors = json_errors,
            .recursive = recursive,
        } },
        .quiet = opts.quiet,
        .strict = opts.strict,
        .json_errors = json_errors or opts.json_errors,
        .import_paths = opts.import_paths,
        .color = opts.color,
        .config_path = opts.config_path,
    };
}

pub fn parseTuneArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    const input = if (fargs.len > 1) fargs[1] else null;
    var dry_run = false;
    for (fargs[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
            break;
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .tune = .{ .input = input, .dry_run = dry_run } }, opts);
}

pub fn parseLspArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    _ = fargs;
    return shared.parseSimpleSubcommand(dialect, target, .lsp, opts);
}


pub fn parseShareArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    var format: types.ShareFormat = .url;
    var output: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var j: usize = 1;
    while (j < fargs.len) : (j += 1) {
        if ((std.mem.eql(u8, fargs[j], "--share-format") or std.mem.eql(u8, fargs[j], "-F")) and j + 1 < fargs.len) {
            j += 1;
            if (std.mem.eql(u8, fargs[j], "json")) {
                format = .json;
            } else if (std.mem.eql(u8, fargs[j], "qr")) {
                format = .qr;
            } else if (!std.mem.eql(u8, fargs[j], "url")) {
                return error.UnknownFormat;
            }
        } else if (std.mem.eql(u8, fargs[j], "-o") and j + 1 < fargs.len) {
            j += 1;
            output = fargs[j];
        } else if (fargs[j][0] != '-') {
            // Positional argument (input file)
            input = fargs[j];
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .share = .{ .input = input, .output = output, .format = format } }, opts);
}

pub fn parseRegistryArgs(fargs: []const []const u8, dialect: dialect_enum.Dialect, target: Target, opts: GlobalFlags) anyerror!ParsedArgs {
    if (fargs.len < 2) return error.MissingArgs;
    const subcmd = fargs[1];
    var name: ?[]const u8 = null;
    var path: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var j: usize = 2;
    while (j < fargs.len) : (j += 1) {
        if ((std.mem.eql(u8, fargs[j], "-o") or std.mem.eql(u8, fargs[j], "--output")) and j + 1 < fargs.len) {
            j += 1;
            output = fargs[j];
        } else if (fargs[j][0] != '-') {
            if (name == null) {
                name = fargs[j];
            } else if (path == null) {
                path = fargs[j];
            }
        }
    }
    return shared.parseSimpleSubcommand(dialect, target, .{ .registry = .{ .subcmd = subcmd, .name = name, .path = path, .output = output } }, opts);
}

