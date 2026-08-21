const std = @import("std");
const cli = @import("cli.zig");
const handlers = @import("pipeline/handlers.zig");
const generate = @import("pipeline/generate.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const migrate_pipe = @import("pipeline/migrate.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");
const version = @import("version.zig");
const completions = @import("completions.zig");
const init_mod = @import("cli/init.zig");
const hooks_mod = @import("cli/hooks.zig");
const config_mod = @import("config.zig");
const config_merge = @import("config_merge.zig");
const fmt = @import("diagnostic/format.zig");
const cli_errors = @import("cli/errors.zig");

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
        cli_errors.handleParseError(err, arg_list);
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
    config_merge.mergeCliConfig(&final_parsed, cfg);

    const home_dir = init.environ_map.get("HOME") orelse init.environ_map.get("USERPROFILE") orelse "/tmp";
    return dispatch(init.io, alloc, final_parsed, home_dir, init.environ_map) catch |err| {
        cli_errors.handleDispatchError(err, final_parsed);
    };
}

fn resolveOutputFormat(target: cli.Target) handlers.OutputFormat {
    return switch (target) {
        .sql => .sql,
        .json_schema => .json_schema,
    };
}

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs, home_dir: []const u8, environ_map: *const std.process.Environ.Map) !void {
    // Handle --init flag (invokes init without explicit subcommand)
    if (parsed.init_flag) {
        return init_mod.handleInit(io, alloc, null, null, null, parsed.dialect, null);
    }

    switch (parsed.command) {
        .version => |cmd| {
            if (cmd.json) version.printVersionJson() else version.printVersion();
            return;
        },
        .help => |cmd| {
            if (cmd.subcommand) |sub| cli.printSubcommandHelp(sub) else cli.printUsage();
            return;
        },
        .compile => |cmd| return handlers.handleCompileRequest(io, alloc, .{
            .input = resolveInputPath(cmd.input),
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
            .cache = cmd.cache,
            .cache_dir = cmd.cache_dir,
            .color = parsed.color.shouldUseColor(io),
        }),
        .validate => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleValidate(io, alloc, file_data, .{ .stats = cmd.stats, .verbose_passes = cmd.verbose_passes, .json_errors = parsed.json_errors, .strict = parsed.strict, .format = cmd.format, .per_table = cmd.per_table, .fix = cmd.fix, .input = cmd.input });
        },
        .check => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleCheck(io, alloc, file_data, .{ .stats = cmd.stats, .verbose_passes = cmd.verbose_passes, .json_errors = parsed.json_errors, .format = cmd.format });
        },
        .stats => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleStats(io, alloc, file_data, .{ .format = cmd.format, .per_table = cmd.per_table, .audit = cmd.audit, .min_score = cmd.min_score });
        },
        .diff => |cmd| return diff_pipe.handleDiff(io, alloc, .{
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
        }),
        .migrate => |cmd| return migrate_pipe.handleMigrate(io, alloc, .{
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
        }),
        .migrate_status => |cmd| return migrate_pipe.handleMigrateStatus(io, alloc, cmd.dir, cmd.json_errors),
        .reverse => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
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
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleDocs(io, alloc, file_data, cmd.output, switch (cmd.doc_format) {
                .markdown => .markdown,
                .json => .json,
            }, parsed.quiet, parsed.dialect);
        },
        .export_cmd => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleExport(io, alloc, file_data, .{ .output = cmd.output, .format = switch (cmd.format) {
                .json => .json,
                .text => .text,
                .markdown => .markdown,
            }, .quiet = parsed.quiet });
        },
        .generate => |cmd| {
            const file_data = if (cmd.list or cmd.check) null else try readFileOrStdin(io, alloc, cmd.input);
            return generate.handleGenerate(io, alloc, file_data, .{
                .generators = cmd.generators_str orelse cmd.generator,
                .output = cmd.output,
                .dialect = parsed.dialect,
                .quiet = parsed.quiet,
                .dry_run = cmd.dry_run,
                .list = cmd.list,
                .check = cmd.check,
                .template_dir = cmd.template_dir,
            }, environ_map);
        },
        .init => |cmd| return init_mod.handleInit(io, alloc, cmd.name, cmd.output, cmd.output_dir, parsed.dialect, cmd.template),
        .format_cmd => |cmd| {
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return handlers.handleFormat(io, alloc, file_data, .{ .output = cmd.output, .check = cmd.check, .diff = cmd.diff, .write = cmd.write, .dialect = cmd.dialect orelse parsed.dialect, .quiet = parsed.quiet, .input_path = cmd.input });
        },
        .completions => |cmd| return completions.handleCompletions(io, alloc, cmd.shell),
        .hooks => |cmd| return hooks_mod.handleHooks(io, alloc, cmd.hook_type),
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
                .include_views = cmd.include_views,
                .summary = cmd.summary,
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
                .stream = cmd.stream,
                .parallel = cmd.parallel,
                .recursive = cmd.recursive,
                .import_paths = parsed.import_paths,
                .color = parsed.color,
            });
        },
        .tune => |cmd| {
            const tune_mod = @import("tune.zig");
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            return tune_mod.handleTune(io, alloc, file_data, cmd.dry_run);
        },
        .registry => |cmd| {
            const registry_cmd = @import("cli/registry_cmd.zig");
            return registry_cmd.handleRegistry(io, alloc, cmd, home_dir);
        },
        .share => |cmd| {
            const share_mod = @import("share.zig");
            const file_data = try readFileOrStdin(io, alloc, cmd.input);
            const share_format = switch (cmd.format) {
                .url => share_mod.ShareFormat.url,
                .json => share_mod.ShareFormat.json,
                .qr => share_mod.ShareFormat.qr,
            };
            return share_mod.handleShare(io, alloc, file_data, .{
                .input = cmd.input,
                .output = cmd.output,
                .format = share_format,
            });
        },
        .lsp => {
            const lsp_server = @import("lsp/server.zig");
            var server = lsp_server.Server.init(alloc, io);
            defer server.deinit();
            return server.run();
        },
    }
}

/// Resolve input path, converting STDIN_PATH to null.
fn resolveInputPath(input: ?[]const u8) ?[]const u8 {
    return if (input) |path|
        if (std.mem.eql(u8, path, io_mod.STDIN_PATH)) null else path
    else
        null;
}

/// Read file or stdin from an optional input path.
fn readFileOrStdin(io: std.Io, alloc: std.mem.Allocator, input: ?[]const u8) ![]const u8 {
    return io_mod.readFileOrStdin(io, alloc, input orelse io_mod.STDIN_PATH);
}

// ─── Input Helpers ───────────────────────────────────────────
