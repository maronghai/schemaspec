const std = @import("std");
const cli = @import("cli.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");
const version = @import("version.zig");
const generator = @import("generator.zig");
const completions = @import("completions.zig");

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
        return forward.handleCompileRequest(init.io, alloc, .{});
    }

    const parsed = cli.parseArgs(alloc, arg_list) catch |err| {
        if (err == error.OutOfMemory) {
            std.debug.print("error: out of memory\n", .{});
        } else if (err == error.UnknownFlag) {
            if (cli.last_unknown_flag) |flag| {
                std.debug.print("error: unknown flag '{s}'. Run 'rune --help' for usage.\n", .{flag});
            } else {
                std.debug.print("error: unknown flag. Run 'rune --help' for usage.\n", .{});
            }
        } else {
            const cli_err: cli.ArgError = @errorCast(err);
            std.debug.print("error: {s}\n", .{cliArgErrorMessage(cli_err)});
        }
        std.process.exit(1);
    };
    return dispatch(init.io, alloc, parsed) catch |err| {
        switch (err) {
            error.DiagnosticsError, error.SemanticError, error.SqlParseError, error.ReverseDiagnosticsError => {
                // Error already printed by the compiler module
            },
            error.CheckFailed => {
                if (!parsed.quiet) {
                    std.debug.print("check failed: schema has differences\n", .{});
                }
                std.process.exit(1);
            },
            else => {
                switch (err) {
                    error.OutOfMemory => std.debug.print("error: out of memory\n", .{}),
                    error.FileNotFound => std.debug.print("error: file not found\n", .{}),
                    error.AccessDenied => std.debug.print("error: access denied\n", .{}),
                    error.IsDir => std.debug.print("error: expected a file, got a directory\n", .{}),
                    error.NotDir => std.debug.print("error: expected a directory, got a file\n", .{}),
                    else => std.debug.print("error: {s}\n", .{@errorName(err)}),
                }
            },
        }
        std.process.exit(1);
    };
}

// ─── Command Dispatch ──────────────────────────────────────────

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs) !void {
    switch (parsed.command) {
        .version => {
            version.printVersion();
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

            return forward.handleCompileRequest(io, alloc, .{
                .input = input_path,
                .output_path = cmd.output,
                .trace = cmd.trace,
                .dialect = parsed.dialect,
                .format = format,
                .stats = cmd.stats,
                .check = cmd.check,
                .quiet = parsed.quiet,
                .verbose_passes = cmd.verbose_passes,
                .json_errors = parsed.json_errors,
                .import_paths = parsed.import_paths,
            });
        },
        .validate => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleValidate(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors, parsed.strict);
        },
        .check => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleCheck(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors);
        },
        .stats => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleStats(io, alloc, file_data);
        },
        .diff => |cmd| {
            return switch (cmd.format) {
                .text => diff_pipe.handleDiff(io, alloc, cmd.old, cmd.new, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
                .json => diff_pipe.handleDiffJson(io, alloc, cmd.old, cmd.new, null, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
                .sarif => diff_pipe.handleDiffSarif(io, alloc, cmd.old, cmd.new, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
            };
        },
        .migrate => |cmd| {
            return switch (cmd.format) {
                .text => diff_pipe.handleMigrate(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.rollback, cmd.stats, cmd.dry_run),
                .json => diff_pipe.handleMigrateDiffJson(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.stats),
                .sarif => diff_pipe.handleMigrate(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.rollback, cmd.stats, cmd.dry_run),
            };
        },
        .reverse => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            const name = cmd.input orelse "<stdin>";
            return reverse_pipe.handleReverse(io, alloc, file_data, name, cmd.output, cmd.with_templates, parsed.dialect, cmd.trace, cmd.stats, cmd.validate_only, cmd.format);
        },
        .docs => |cmd| {
            if (generator.get("docs")) |gen| {
                const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
                const pipeline = try forward.compilePipeline(alloc, file_data);
                const typed = try @import("types/type_resolver.zig").TypeResolver.resolve(alloc, pipeline.resolved, parsed.dialect);
                const output_text = try gen.generate(alloc, typed, parsed.dialect);
                try io_mod.writeOutput(io, output_text, cmd.output, parsed.quiet);
            }
        },
        .generate => |cmd| {
            if (cmd.list) {
                generator.listAll();
                return;
            }
            if (generator.get(cmd.generator)) |gen| {
                const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
                const pipeline = try forward.compilePipeline(alloc, file_data);
                const typed = try @import("types/type_resolver.zig").TypeResolver.resolve(alloc, pipeline.resolved, parsed.dialect);
                const output_text = try gen.generate(alloc, typed, parsed.dialect);
                try io_mod.writeOutput(io, output_text, cmd.output, parsed.quiet);
            } else {
                std.debug.print("error: unknown generator '{s}'. Run 'rune generate --list' for available generators.\n", .{cmd.generator});
                std.process.exit(1);
            }
        },
        .init => |cmd| {
            return completions.handleInit(io, alloc, cmd.name, cmd.output);
        },
        .format_cmd => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            const formatter = @import("formatter.zig");
            const formatted = try formatter.format(alloc, file_data);
            try io_mod.writeOutput(io, formatted, cmd.output, parsed.quiet);
        },
        .completions => |cmd| {
            return completions.handleCompletions(io, alloc, cmd.shell);
        },
    }
}

// ─── Error Messages ───────────────────────────────────────────

/// Map CLI argument errors to human-readable messages.
fn cliArgErrorMessage(err: cli.ArgError) []const u8 {
    return switch (err) {
        error.UnknownDialect => "unknown dialect, expected one of: mysql, pg, postgres, sqlite, mssql, oracle, db2",
        error.MissingDialectValue => "--dialect requires a value, expected one of: mysql, pg, postgres, sqlite, mssql, oracle, db2",
        error.UnknownTarget => "unknown target, expected one of: sql, json-schema",
        error.MissingTargetValue => "--target requires a value, expected one of: sql, json-schema",
        error.UnknownFormat => "unknown format, expected one of: text, json, sarif",
        error.DiffMissingArgs => "diff requires two arguments: <old.ss> <new.ss>",
        error.MigrateMissingArgs => "migrate requires two arguments: <old.ss> <new.ss>",
        error.UnknownCommand => "unknown command. Run 'rune --help' for usage.",
        error.UnknownFlag => "unknown flag. Run 'rune --help' for usage.",
    };
}
