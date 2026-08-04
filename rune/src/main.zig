const std = @import("std");
const cli = @import("cli.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");
const version = @import("version.zig");
const generator = @import("generator.zig");
const completions = @import("completions.zig");
const config_mod = @import("config.zig");

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
        handleParseError(err, arg_list);
    };

    // Load project config (rune.toml) and apply defaults
    var final_parsed = parsed;
    const config_path = parsed.config_path orelse "rune.toml";
    const cfg = config_mod.loadConfig(init.io, alloc, config_path) catch blk: {
        break :blk config_mod.Config{};
    };
    // Validate config values
    config_mod.validateConfig(cfg) catch |err| {
        switch (err) {
            error.InvalidDialect => std.debug.print("error: invalid dialect '{s}' in {s}\n", .{ cfg.dialect.?, config_path }),
            error.InvalidColor => std.debug.print("error: invalid color '{s}' in {s}. Expected: auto, always, never\n", .{ cfg.color.?, config_path }),
        }
        std.process.exit(1);
    };
    // Apply config defaults (CLI flags take precedence)
    if (parsed.dialect == .mysql and cfg.dialect != null) {
        final_parsed.dialect = cli.parseDialect(cfg.dialect.?) catch parsed.dialect;
    }
    if (cfg.quiet != null and !parsed.quiet) final_parsed.quiet = cfg.quiet.?;
    if (cfg.json_errors != null and !parsed.json_errors) final_parsed.json_errors = cfg.json_errors.?;
    if (cfg.color != null) {
        final_parsed.color = if (std.mem.eql(u8, cfg.color.?, "always"))
            .always
        else if (std.mem.eql(u8, cfg.color.?, "never"))
            .never
        else
            parsed.color;
    }

    return dispatch(init.io, alloc, final_parsed) catch |err| {
        handleDispatchError(err, final_parsed);
    };
}

// ─── Error Handling ────────────────────────────────────────────

fn handleParseError(err: anyerror, arg_list: []const []const u8) noreturn {
    if (err == error.OutOfMemory) {
        std.debug.print("error: out of memory\n", .{});
    } else if (err == error.UnknownFlag) {
        if (cli.findUnknownFlag(arg_list)) |flag| {
            if (cli.suggestSimilarFlag(flag)) |suggestion| {
                std.debug.print("error: unknown flag '{s}'. Did you mean '{s}'?\n", .{ flag, suggestion });
            } else {
                std.debug.print("error: unknown flag '{s}'. Run 'rune --help' for usage.\n", .{flag});
            }
        } else {
            std.debug.print("error: unknown flag. Run 'rune --help' for usage.\n", .{});
        }
    } else if (err == error.UnknownCommand) {
        std.debug.print("error: unknown command '{s}'. Available commands:\n", .{arg_list[1]});
        inline for (cli.COMMAND_REGISTRY) |cmd| {
            std.debug.print("  {s}\n", .{cmd.name});
        }
    } else if (err == error.UnknownGenerator) {
        std.debug.print("error: unknown generator. Available generators:\n", .{});
        for (generator.REGISTRY) |gen| {
            std.debug.print("  {s}\n", .{gen.name});
        }
    } else {
        const cli_err: cli.ArgError = @errorCast(err);
        std.debug.print("error: {s}\n", .{cliArgErrorMessage(cli_err)});
    }
    std.process.exit(1);
}

fn handleDispatchError(err: anyerror, parsed: cli.ParsedArgs) noreturn {
    switch (err) {
        error.DiagnosticsError, error.SemanticError, error.SqlParseError, error.ReverseDiagnosticsError => {},
        error.CheckFailed => {
            if (!parsed.quiet) {
                std.debug.print("check failed: schema has differences\n", .{});
            }
            std.debug.print("", .{});
            std.process.exit(1);
        },
        error.UnknownGenerator => {
            std.debug.print("error: unknown generator. Available generators:\n", .{});
            for (generator.REGISTRY) |gen| {
                std.debug.print("  {s}\n", .{gen.name});
            }
            std.process.exit(1);
        },
        error.OutOfMemory => std.debug.print("error: out of memory\n", .{}),
        error.FileNotFound => {
            const input_path = getInputPath(parsed.command);
            const input_path2 = getInputPath2(parsed.command);
            if (input_path) |path| {
                if (input_path2) |path2| {
                    std.debug.print("error: file not found: {s} or {s}\n", .{ path, path2 });
                } else {
                    std.debug.print("error: file not found: {s}\n", .{path});
                }
            } else {
                std.debug.print("error: file not found\n", .{});
            }
        },
        error.AccessDenied => std.debug.print("error: access denied\n", .{}),
        error.IsDir => std.debug.print("error: expected a file, got a directory\n", .{}),
        error.NotDir => std.debug.print("error: expected a directory, got a file\n", .{}),
        error.UnknownShell => std.debug.print("error: unknown shell. Expected: bash, zsh, fish, powershell\n", .{}),
        else => std.debug.print("error: {s}\n", .{@errorName(err)}),
    }
    std.process.exit(1);
}

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs) !void {
    // Handle --init flag (invokes init without explicit subcommand)
    if (parsed.init_flag) {
        return completions.handleInit(io, alloc, null, null, parsed.dialect);
    }

    switch (parsed.command) {
        .version => {
            version.printVersion();
            return;
        },
        .help => |cmd| {
            if (cmd.subcommand) |sub| {
                cli.printSubcommandHelp(sub);
            } else {
                cli.printUsage();
            }
            return;
        },
        .compile => |cmd| {
            const input_path = if (cmd.input) |path|
                if (std.mem.eql(u8, path, io_mod.STDIN_PATH)) null else path
            else
                null;

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
                .stream = cmd.stream,
            });
        },
        .validate => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return forward.handleValidate(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors, parsed.strict);
        },
        .check => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return forward.handleCheck(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors);
        },
        .stats => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return forward.handleStats(io, alloc, file_data, cmd.format == .json);
        },
        .diff => |cmd| {
            return diff_pipe.handleDiff(io, alloc, .{
                .old_path = cmd.old,
                .new_path = cmd.new,
                .dialect = parsed.dialect,
                .format = cmd.format,
                .trace = cmd.trace,
                .stats = cmd.stats,
                .check = cmd.check,
                .color = parsed.color,
                .summary = cmd.summary,
            });
        },
        .migrate => |cmd| {
            return diff_pipe.handleMigrate(io, alloc, .{
                .old_path = cmd.old,
                .new_path = cmd.new,
                .dialect = parsed.dialect,
                .format = cmd.format,
                .output_path = cmd.output,
                .trace = cmd.trace,
                .stats = cmd.stats,
                .rollback = cmd.rollback,
                .dry_run = cmd.dry_run,
                .check = cmd.check,
                .name = cmd.name,
                .dir = cmd.dir,
                .incremental = cmd.incremental,
                .summary = cmd.summary,
                .color = parsed.color,
                .graph = cmd.graph,
            });
        },
        .migrate_status => |cmd| {
            return diff_pipe.handleMigrateStatus(io, alloc, cmd.dir, cmd.json_errors);
        },
        .reverse => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return reverse_pipe.handleReverse(io, alloc, file_data, .{
                .input_name = cmd.input orelse "<stdin>",
                .output_path = cmd.output,
                .dialect = parsed.dialect,
                .format = cmd.format,
                .with_templates = cmd.with_templates,
                .trace = cmd.trace,
                .stats = cmd.stats,
                .validate_only = cmd.validate_only,
            });
        },
        .docs => |cmd| {
            // Shortcut for `rune generate docs` — both route through the same generator registry
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return forward.generateFromSchema(io, alloc, file_data, "docs", parsed.dialect, cmd.output, parsed.quiet);
        },
        .generate => |cmd| {
            if (cmd.list) {
                generator.listAll();
                return;
            }
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return forward.generateFromSchema(io, alloc, file_data, cmd.generator, parsed.dialect, cmd.output, parsed.quiet);
        },
        .init => |cmd| {
            return completions.handleInit(io, alloc, cmd.name, cmd.output, parsed.dialect);
        },
        .format_cmd => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
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

/// Extract the input file path from a Command for error messages.
fn getInputPath(command: cli.Command) ?[]const u8 {
    return switch (command) {
        .compile => |cmd| cmd.input,
        .validate => |cmd| cmd.input,
        .check => |cmd| cmd.input,
        .stats => |cmd| cmd.input,
        .diff => |cmd| cmd.old,
        .migrate => |cmd| cmd.old,
        .reverse => |cmd| cmd.input,
        .docs => |cmd| cmd.input,
        .format_cmd => |cmd| cmd.input,
        .generate => |cmd| cmd.input,
        else => null,
    };
}

/// Extract the second input file path (for diff/migrate) for error messages.
fn getInputPath2(command: cli.Command) ?[]const u8 {
    return switch (command) {
        .diff => |cmd| cmd.new,
        .migrate => |cmd| cmd.new,
        else => null,
    };
}

/// Map CLI argument errors to human-readable messages.
fn cliArgErrorMessage(err: cli.ArgError) []const u8 {
    return switch (err) {
        error.UnknownDialect => "unknown dialect, expected one of: mysql, pg, postgres, sqlite, mssql, oracle, db2",
        error.MissingDialectValue => "--dialect requires a value, expected one of: mysql, pg, postgres, sqlite, mssql, oracle, db2",
        error.UnknownTarget => "unknown target, expected one of: sql, json-schema",
        error.MissingTargetValue => "--target requires a value, expected one of: sql, json-schema",
        error.UnknownFormat => "unknown format, expected one of: text, json, sarif, markdown",
        error.DiffMissingArgs => "diff requires two arguments: <old.ss> <new.ss>",
        error.MigrateMissingArgs => "migrate requires two arguments: <old.ss> <new.ss>",
        error.UnknownCommand => "unknown command. Run 'rune --help' for usage.",
        error.UnknownFlag => "unknown flag. Run 'rune --help' for usage.",
        error.UnknownGenerator => "unknown generator. Run 'rune generate --list' for available generators.",
        error.UnknownShell => "unknown shell. Expected: bash, zsh, fish, powershell.",
    };
}
