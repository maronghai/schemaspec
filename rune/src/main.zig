const std = @import("std");
const cli = @import("cli.zig");
const handlers = @import("pipeline/handlers.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");
const version = @import("version.zig");
const generator = @import("generator.zig");
const completions = @import("completions.zig");
const init_mod = @import("cli/init.zig");
const hooks_mod = @import("cli/hooks.zig");
const config_mod = @import("config.zig");
const dialect_enum = @import("dialect/enum.zig");
const fmt = @import("diagnostic/format.zig");

// ─── Windows UTF-8 Console Support ──────────────────────────────

extern "kernel32" fn SetConsoleOutputCP(codepage: u32) callconv(.winapi) c_int;
extern "kernel32" fn SetConsoleCP(codepage: u32) callconv(.winapi) c_int;

fn enableWindowsUtf8() void {
    if (comptime @import("builtin").os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
    }
}

// ─── Entry Point ───────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    enableWindowsUtf8();
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
        return handlers.handleCompileRequest(init.io, alloc, .{});
    }

    const parsed = cli.parseArgs(alloc, arg_list) catch |err| {
        handleParseError(err, arg_list);
    };

    // Load project config (rune.toml) and apply defaults
    // When no explicit --config flag, search upward from cwd (like git searches for .git/).
    var final_parsed = parsed;
    const cfg = e: {
        if (parsed.config_path) |path| {
            break :e config_mod.loadConfigWithWarnings(init.io, alloc, path) catch {
                fmt.printWarn("failed to load config file, using defaults");
                break :e config_mod.Config{};
            };
        } else {
            break :e config_mod.loadConfigWithDiscoveryAndWarnings(init.io, alloc) catch {
                fmt.printWarn("failed to load config, using defaults");
                break :e config_mod.Config{};
            };
        }
    };
    // Validate config values
    config_mod.validateConfig(cfg) catch |err| {
        switch (err) {
            error.InvalidDialect => fmt.printError("config", "invalid dialect in config"),
            error.InvalidColor => fmt.printError("config", "invalid color in config. Expected: auto, always, never"),
            error.InvalidTarget => fmt.printError("config", "invalid target in config. Expected: sql, json-schema"),
            error.InvalidFormat => fmt.printError("config", "invalid format in config. Expected: text, json, sarif, markdown"),
        }
        std.process.exit(1);
    };
    // Apply config defaults (CLI flags take precedence)
    if (!parsed.dialect_was_explicit and cfg.dialect != null) {
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
    if (cfg.target != null and !parsed.dialect_was_explicit) {
        final_parsed.target = cli.parseTarget(cfg.target.?) catch parsed.target;
    }
    // Apply stream/parallel/format defaults to subcommand structs
    if (cfg.stream != null and final_parsed.command == .compile) {
        final_parsed.command.compile.stream = final_parsed.command.compile.stream or cfg.stream.?;
    }
    if (cfg.parallel != null) {
        if (final_parsed.command == .compile) {
            final_parsed.command.compile.parallel = final_parsed.command.compile.parallel or cfg.parallel.?;
        } else if (final_parsed.command == .watch) {
            final_parsed.command.watch.parallel = final_parsed.command.watch.parallel or cfg.parallel.?;
        }
    }

    return dispatch(init.io, alloc, final_parsed) catch |err| {
        handleDispatchError(err, final_parsed);
    };
}

// ─── Error Handling ────────────────────────────────────────────

fn printAvailableGenerators() void {
    std.debug.print("Available generators:\n", .{});
    for (generator.REGISTRY) |gen| {
        std.debug.print("  {s}\n", .{gen.name});
    }
}

fn resolveOutputFormat(target: cli.Target) handlers.OutputFormat {
    return switch (target) {
        .sql => .sql,
        .json_schema => .json_schema,
    };
}

fn handleParseError(err: anyerror, arg_list: []const []const u8) noreturn {
    if (err == error.OutOfMemory) {
        fmt.printErr("out of memory");
        fmt.printErr("  hint: try reducing schema file size or increasing system memory");
    } else if (err == error.UnknownFlag) {
        if (cli.findUnknownFlag(arg_list)) |flag| {
            if (cli.suggestSimilarFlag(flag)) |suggestion| {
                fmt.printError("cli", "unknown flag. Did you mean?");
                std.debug.print("  {s}\n", .{suggestion});
            } else {
                fmt.printError("cli", "unknown flag. Run 'rune --help' for usage.");
            }
        } else {
            fmt.printError("cli", "unknown flag. Run 'rune --help' for usage.");
        }
    } else if (err == error.UnknownCommand) {
        fmt.printError("cli", "unknown command. Available commands:");
        inline for (cli.COMMAND_REGISTRY) |cmd| {
            std.debug.print("  {s}\n", .{cmd.name});
        }
    } else if (err == error.UnknownGenerator) {
        printAvailableGenerators();
    } else {
        const cli_err: cli.ArgError = @errorCast(err);
        fmt.printError("cli", cliArgErrorMessage(cli_err));
    }
    std.process.exit(1);
}

fn handleDispatchError(err: anyerror, parsed: cli.ParsedArgs) noreturn {
    switch (err) {
        error.DiagnosticsError, error.SemanticError, error.SqlParseError, error.ReverseDiagnosticsError => {},
        error.CheckFailed => {
            if (!parsed.quiet) {
                fmt.printErr("check failed: schema has differences");
            }
            std.process.exit(1);
        },
        error.FormatCheckFailed => {
            if (!parsed.quiet) {
                fmt.printErr("format check failed: file needs formatting");
            }
            std.process.exit(1);
        },
        error.UnknownGenerator => {
            printAvailableGenerators();
            std.process.exit(1);
        },
        error.OutOfMemory => {
            fmt.printErr("out of memory");
            fmt.printErr("  hint: try reducing schema file size, using --import-path for large schemas, or increasing system memory");
        },
        error.UnknownHookType => {
            fmt.printError("cli", "unknown hook type. Available: pre-commit");
            std.process.exit(1);
        },
        error.FileNotFound => {
            const paths = getInputPaths(parsed.command);
            if (paths.path1) |path| {
                if (paths.path2) |path2| {
                    fmt.printError("io", "file not found");
                    std.debug.print("  {s} or {s}\n", .{ path, path2 });
                } else {
                    fmt.printError("io", "file not found");
                    std.debug.print("  {s}\n", .{path});
                }
            } else {
                fmt.printError("io", "file not found");
            }
            fmt.printErr("  hint: check the file path and ensure the file exists");
        },
        error.AccessDenied => {
            fmt.printError("io", "access denied");
            fmt.printErr("  hint: check file permissions or run with appropriate user");
        },
        error.NoSpaceLeft => {
            fmt.printError("io", "no space left on device");
            fmt.printErr("  hint: free disk space or choose a different output path");
        },
        error.IsDir => fmt.printError("io", "expected a file, got a directory"),
        error.NotDir => fmt.printError("io", "expected a directory, got a file"),
        error.UnknownShell => fmt.printError("cli", "unknown shell. Expected: bash, zsh, fish, powershell"),
        else => fmt.printErr(@errorName(err)),
    }
    std.process.exit(1);
}

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs) !void {
    // Handle --init flag (invokes init without explicit subcommand)
    if (parsed.init_flag) {
        return init_mod.handleInit(io, alloc, null, null, null, parsed.dialect, null);
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

            return handlers.handleCompileRequest(io, alloc, .{
                .input = input_path,
                .output_path = cmd.output,
                .trace = cmd.trace,
                .dialect = parsed.dialect,
                .format = resolveOutputFormat(parsed.target),
                .stats = cmd.stats,
                .check = cmd.check,
                .quiet = parsed.quiet,
                .verbose_passes = cmd.verbose_passes,
                .json_errors = parsed.json_errors,
                .import_paths = parsed.import_paths,
                .stream = cmd.stream,
                .parallel = cmd.parallel,
                .color = parsed.color.shouldUseColor(io),
            });
        },
        .validate => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return handlers.handleValidate(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors, parsed.strict, cmd.format, cmd.per_table);
        },
        .check => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return handlers.handleCheck(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors, cmd.format);
        },
        .stats => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return handlers.handleStats(io, alloc, file_data, cmd.format, cmd.per_table);
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
                .from_sql = cmd.from_sql,
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
                .auto_lint = !cmd.no_lint,
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
                .check = cmd.check,
            });
        },
        .docs => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            const doc_format: handlers.DocsFormat = switch (cmd.doc_format) {
                .markdown => .markdown,
                .json => .json,
            };
            return handlers.handleDocs(io, alloc, file_data, cmd.output, doc_format, parsed.quiet, parsed.dialect);
        },
        .generate => |cmd| {
            if (cmd.list) {
                generator.listAll();
                return;
            }
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            // Batch generation: --generators prisma,drizzle,openapi
            if (cmd.generators_str) |gens_str| {
                return handlers.generateFromSchemaBatch(io, alloc, file_data, gens_str, parsed.dialect, cmd.output, parsed.quiet, cmd.dry_run);
            }
            return handlers.generateFromSchema(io, alloc, file_data, cmd.generator, parsed.dialect, cmd.output, parsed.quiet, cmd.dry_run);
        },
        .init => |cmd| {
            return init_mod.handleInit(io, alloc, cmd.name, cmd.output, cmd.output_dir, parsed.dialect, cmd.template);
        },
        .format_cmd => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return handlers.handleFormat(io, alloc, file_data, cmd.output, cmd.check, parsed.quiet);
        },
        .completions => |cmd| {
            return completions.handleCompletions(io, alloc, cmd.shell);
        },
        .hooks => |cmd| {
            return hooks_mod.handleHooks(io, alloc, cmd.hook_type);
        },
        .lint => |cmd| {
            const lint_cmd = @import("cli/lint_cmd.zig");
            return lint_cmd.handleLint(io, alloc, .{
                .input = cmd.input,
                .input2 = cmd.input2,
                .json_errors = cmd.json_errors,
                .strict = cmd.strict,
                .format = cmd.format,
                .rules = cmd.rules,
                .fix = cmd.fix,
                .dry_run = cmd.dry_run,
            }, parsed);
        },
        .watch => |cmd| {
            const watch_mod = @import("watch.zig");
            return watch_mod.watch(io, alloc, .{
                .input = cmd.input,
                .interval_ms = cmd.interval_ms,
                .dialect = parsed.dialect,
                .target = resolveOutputFormat(parsed.target),
                .output_path = cmd.output,
                .quiet = parsed.quiet,
                .trace = cmd.trace,
                .stats = cmd.stats,
                .json_errors = cmd.json_errors,
                .parallel = cmd.parallel,
                .recursive = cmd.recursive,
            });
        },
        .tune => |cmd| {
            const tune_mod = @import("tune.zig");
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
            return tune_mod.handleTune(io, alloc, file_data, cmd.dry_run);
        },
        .lsp => {
            const lsp_server = @import("lsp/server.zig");
            var server = lsp_server.Server.init(alloc, io);
            defer server.deinit();
            return server.run();
        },
    }
}

// ─── Error Messages ───────────────────────────────────────────

/// Result of extracting input paths from a Command for error messages.
const InputPaths = struct {
    path1: ?[]const u8 = null,
    path2: ?[]const u8 = null,
};

/// Extract input file paths from a Command for error messages.
/// Returns both primary and secondary paths (for diff/migrate commands).
fn getInputPaths(command: cli.Command) InputPaths {
    return switch (command) {
        .compile => |cmd| .{ .path1 = cmd.input },
        .validate => |cmd| .{ .path1 = cmd.input },
        .check => |cmd| .{ .path1 = cmd.input },
        .stats => |cmd| .{ .path1 = cmd.input },
        .diff => |cmd| .{ .path1 = cmd.old, .path2 = cmd.new },
        .migrate => |cmd| .{ .path1 = cmd.old, .path2 = cmd.new },
        .reverse => |cmd| .{ .path1 = cmd.input },
        .docs => |cmd| .{ .path1 = cmd.input },
        .format_cmd => |cmd| .{ .path1 = cmd.input },
        .generate => |cmd| .{ .path1 = cmd.input },
        .lint => |cmd| .{ .path1 = cmd.input },
        .watch => |cmd| .{ .path1 = cmd.input },
        .tune => |cmd| .{ .path1 = cmd.input },
        else => .{},
    };
}

/// Map CLI argument errors to human-readable messages.
fn cliArgErrorMessage(err: cli.ArgError) []const u8 {
    return switch (err) {
        error.UnknownDialect => "unknown dialect, expected one of: " ++ dialect_enum.VALID_NAMES_CSV,
        error.MissingDialectValue => "--dialect requires a value, expected one of: " ++ dialect_enum.VALID_NAMES_CSV,
        error.UnknownTarget => "unknown target, expected one of: sql, json-schema",
        error.MissingTargetValue => "--target requires a value, expected one of: sql, json-schema",
        error.UnknownFormat => "unknown format, expected one of: text, json, sarif, markdown",
        error.MissingFormatValue => "--format requires a value, expected one of: text, json, sarif, markdown",
        error.MissingConfigValue => "--config requires a value (config file path)",
        error.MissingImportPathValue => "--import-path requires a value (search path)",
        error.DiffMissingArgs => "diff requires two arguments: <old.ss> <new.ss>",
        error.MigrateMissingArgs => "migrate requires two arguments: <old.ss> <new.ss>",
        error.MissingArgs => "missing required argument. Run 'rune <command> --help' for usage.",
        error.UnknownCommand => "unknown command. Run 'rune --help' for usage.",
        error.UnknownFlag => "unknown flag. Run 'rune --help' for usage.",
        error.UnknownGenerator => "unknown generator. Run 'rune generate --list' for available generators.",
        error.UnknownShell => "unknown shell. Expected: bash, zsh, fish, powershell.",
        error.UnknownHookType => "unknown hook type. Available: pre-commit.",
    };
}
