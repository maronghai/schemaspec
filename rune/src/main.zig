const std = @import("std");
const cli = @import("cli.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");

// ─── Entry Point ───────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var args = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer arg_it.deinit();
    while (arg_it.next()) |arg| {
        try args.append(alloc, arg);
    }
    const arg_list = try args.toOwnedSlice(alloc);

    // No args: check stdin pipe vs interactive terminal
    if (arg_list.len < 2) {
        const is_tty = std.Io.File.stdin().isTty(init.io) catch true;
        if (is_tty) {
            cli.printUsage();
            std.process.exit(1);
        }
        return forward.handleCompileRequest(init.io, alloc, null, null, false, .mysql, .sql, false, false, false);
    }

    const parsed = cli.parseArgs(alloc, arg_list) catch |err| {
        switch (err) {
            error.UnknownDialect => {
                std.debug.print("error: unknown dialect (expected: mysql, pg, postgres, sqlite)\n", .{});
            },
            error.MissingDialectValue => {
                std.debug.print("error: --dialect requires a value (mysql, pg, postgres, sqlite)\n", .{});
            },
            error.UnknownTarget => {
                std.debug.print("error: unknown target (expected: sql, json-schema)\n", .{});
            },
            error.MissingTargetValue => {
                std.debug.print("error: --target requires a value (sql, json-schema)\n", .{});
            },
            error.DiffMissingArgs => {
                std.debug.print("error: diff requires <old.ss> <new.ss>\n", .{});
            },
            error.MigrateMissingArgs => {
                std.debug.print("error: migrate requires <old.ss> <new.ss>\n", .{});
            },
            else => {
                std.debug.print("error: {s}\n", .{@errorName(err)});
            },
        }
        std.process.exit(1);
    };
    return dispatch(init.io, alloc, parsed) catch |err| {
        switch (err) {
            error.DiagnosticsError, error.SemanticError, error.SqlParseError, error.ReverseDiagnosticsError => {
                // Error already printed by the compiler module
            },
            else => {
                std.debug.print("error: {s}\n", .{@errorName(err)});
            },
        }
        std.process.exit(1);
    };
}

const VERSION = "0.22.0";

// ─── Command Dispatch ──────────────────────────────────────────

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs) !void {
    switch (parsed.command) {
        .version => {
            std.debug.print("rune {s}\n", .{VERSION});
            return;
        },
        .help => {
            cli.printUsage();
            return;
        },
        .compile => |cmd| {
            // Determine input path (null = stdin, "-" = stdin, else = file)
            const input_path = if (cmd.input) |path|
                if (std.mem.eql(u8, path, "-")) null else path
            else
                null;

            // Determine output format
            const format: forward.OutputFormat = switch (parsed.target) {
                .sql => .sql,
                .json_schema => .json_schema,
            };

            return forward.handleCompileRequest(io, alloc, input_path, cmd.output, cmd.trace, parsed.dialect, format, cmd.stats, cmd.check, parsed.quiet);
        },
        .validate => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleValidate(io, alloc, file_data, cmd.stats);
        },
        .diff => |cmd| {
            return switch (parsed.target) {
                .sql => diff_pipe.handleDiff(io, alloc, cmd.old, cmd.new, parsed.dialect, cmd.trace, cmd.stats),
                .json_schema => diff_pipe.handleDiffJson(io, alloc, cmd.old, cmd.new, null, parsed.dialect, cmd.trace, cmd.stats),
            };
        },
        .migrate => |cmd| {
            return switch (parsed.target) {
                .sql => diff_pipe.handleMigrate(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.rollback, cmd.stats),
                .json_schema => diff_pipe.handleMigrateDiffJson(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.stats),
            };
        },
        .reverse => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            const name = cmd.input orelse "<stdin>";
            return reverse_pipe.handleReverse(io, alloc, file_data, name, cmd.output, cmd.with_templates, parsed.dialect, cmd.trace, cmd.stats);
        },
    }
}
