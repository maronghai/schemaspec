const std = @import("std");
const dialect_enum = @import("dialect/enum.zig");

// ─── Command Types ─────────────────────────────────────────────

pub const Target = enum { sql, json_schema };

pub const Command = union(enum) {
    compile: struct { input: ?[]const u8, output: ?[]const u8, trace: bool },
    validate: struct { input: ?[]const u8 },
    diff: struct { old: []const u8, new: []const u8, trace: bool },
    migrate: struct { old: []const u8, new: []const u8, output: ?[]const u8, trace: bool },
    reverse: struct { input: ?[]const u8, output: ?[]const u8, with_templates: bool, trace: bool },
    version,
};

pub const ParsedArgs = struct {
    dialect: dialect_enum.Dialect,
    target: Target,
    command: Command,
};

pub const ArgError = error{
    UnknownDialect,
    MissingDialectValue,
    UnknownTarget,
    MissingTargetValue,
    DiffMissingArgs,
    MigrateMissingArgs,
};

// ─── Shared Flag Parsers ───────────────────────────────────────

/// Scan args for `-o <path>` and return the output path (or null).
fn parseOutputFlag(args: []const []const u8, start: usize) ?[]const u8 {
    var j: usize = start;
    while (j < args.len) : (j += 1) {
        if (std.mem.eql(u8, args[j], "-o") and j + 1 < args.len) {
            return args[j + 1];
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

    // Pass 1: extract --dialect / -d / --target / --version / -v from all args
    var i: usize = 1; // skip argv[0]
    var want_version = false;
    while (i < raw_args.len) : (i += 1) {
        if (std.mem.eql(u8, raw_args[i], "--version") or std.mem.eql(u8, raw_args[i], "-v")) {
            want_version = true;
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
        } else {
            try filtered.append(alloc, raw_args[i]);
        }
    }
    const fargs = try filtered.toOwnedSlice(alloc);

    if (want_version) {
        return .{ .dialect = dialect, .target = target, .command = .version };
    }

    // Pass 2: route subcommand
    if (fargs.len < 1) {
        return .{ .dialect = dialect, .target = target, .command = .{ .compile = .{ .input = null, .output = null, .trace = false } } };
    }

    const sub = fargs[0];

    if (std.mem.eql(u8, sub, "diff")) {
        if (fargs.len < 3) return error.DiffMissingArgs;
        return .{ .dialect = dialect, .target = target, .command = .{ .diff = .{ .old = fargs[1], .new = fargs[2], .trace = parseTraceFlag(fargs, 3) } } };
    }

    if (std.mem.eql(u8, sub, "migrate")) {
        if (fargs.len < 3) return error.MigrateMissingArgs;
        return .{ .dialect = dialect, .target = target, .command = .{ .migrate = .{ .old = fargs[1], .new = fargs[2], .output = parseOutputFlag(fargs, 3), .trace = parseTraceFlag(fargs, 3) } } };
    }

    if (std.mem.eql(u8, sub, "reverse")) {
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
        return .{ .dialect = dialect, .target = target, .command = .{ .reverse = .{ .input = input, .output = parseOutputFlag(fargs, 1), .with_templates = with_templates, .trace = parseTraceFlag(fargs, 1) } } };
    }

    if (std.mem.eql(u8, sub, "validate")) {
        const input = if (fargs.len > 1) fargs[1] else null;
        return .{ .dialect = dialect, .target = target, .command = .{ .validate = .{ .input = input } } };
    }

    // Default: compile
    const input = if (fargs.len > 0) fargs[0] else null;
    return .{ .dialect = dialect, .target = target, .command = .{ .compile = .{ .input = input, .output = parseOutputFlag(fargs, 1), .trace = parseTraceFlag(fargs, 1) } } };
}

fn parseDialect(s: []const u8) !dialect_enum.Dialect {
    if (std.mem.eql(u8, s, "mysql")) return .mysql;
    if (std.mem.eql(u8, s, "pg") or std.mem.eql(u8, s, "postgres")) return .pg;
    if (std.mem.eql(u8, s, "sqlite") or std.mem.eql(u8, s, "sq")) return .sqlite;
    return error.UnknownDialect;
}

fn parseTarget(s: []const u8) !Target {
    if (std.mem.eql(u8, s, "sql")) return .sql;
    if (std.mem.eql(u8, s, "json-schema") or std.mem.eql(u8, s, "json_schema")) return .json_schema;
    return error.UnknownTarget;
}

// ─── Usage ─────────────────────────────────────────────────────

pub fn printUsage() void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("  rune [input.ss] [-o output] [--trace] [-d mysql|pg|sqlite] [--target sql|json-schema]\n", .{});
    std.debug.print("                                                       Compile .ss to SQL DDL or JSON Schema\n", .{});
    std.debug.print("  rune validate [input.ss]                             Validate .ss schema (no output)\n", .{});
    std.debug.print("  rune diff <old.ss> <new.ss> [-d mysql|pg|sqlite]     Show schema differences\n", .{});
    std.debug.print("  rune migrate <old.ss> <new.ss> [-o migration.sql] [-d mysql|pg|sqlite]\n", .{});
    std.debug.print("                                                       Generate ALTER TABLE migration SQL\n", .{});
    std.debug.print("  rune reverse [input.sql] [-o output.ss] [-T] [-d mysql|pg|sqlite]\n", .{});
    std.debug.print("                                                       Reverse SQL DDL to .ss schema\n", .{});
    std.debug.print("                                                       -T: extract shared templates\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  -d, --dialect   Target SQL dialect: mysql (default), pg, postgres, sqlite\n", .{});
    std.debug.print("  --target        Output format: sql (default), json-schema\n", .{});
    std.debug.print("  --trace         Print intermediate pipeline stages for debugging\n", .{});
    std.debug.print("  -v, --version   Print version and exit\n", .{});
    std.debug.print("\nPipe mode: read from stdin when no input file is given.\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune\n", .{});
    std.debug.print("  echo '# t\\nid n' | rune --target json-schema\n", .{});
    std.debug.print("  cat schema.sql | rune reverse -T\n", .{});
}
