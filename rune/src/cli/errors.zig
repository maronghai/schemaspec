const std = @import("std");
const cli = @import("../cli.zig");
const dialect_enum = @import("../dialect/enum.zig");
const fmt = @import("../diagnostic/format.zig");
const generator = @import("../generator.zig");

// ─── CLI Error Handling ──────────────────────────────────────
// Error-to-message mapping extracted from main.zig for single-responsibility.
// Used by the main dispatch loop to present user-friendly error messages.

/// Result of extracting input paths from a Command for error messages.
pub const InputPaths = struct {
    path1: ?[]const u8 = null,
    path2: ?[]const u8 = null,
};

/// Extract input file paths from a Command for error messages.
/// Returns both primary and secondary paths (for diff/migrate commands).
pub fn getInputPaths(command: cli.Command) InputPaths {
    return switch (command) {
        .compile => |cmd| .{ .path1 = cmd.input },
        .validate => |cmd| .{ .path1 = cmd.input },
        .check => |cmd| .{ .path1 = cmd.input },
        .stats => |cmd| .{ .path1 = cmd.input },
        .diff => |cmd| .{ .path1 = cmd.old, .path2 = cmd.new },
        .migrate => |cmd| .{ .path1 = cmd.old, .path2 = cmd.new },
        .reverse => |cmd| .{ .path1 = cmd.input },
        .docs => |cmd| .{ .path1 = cmd.input },
        .export_cmd => |cmd| .{ .path1 = cmd.input },
        .format_cmd => |cmd| .{ .path1 = cmd.input },
        .generate => |cmd| .{ .path1 = cmd.input },
        .lint => |cmd| .{ .path1 = cmd.input },
        .watch => |cmd| .{ .path1 = cmd.input },
        .tune => |cmd| .{ .path1 = cmd.input },
        else => .{},
    };
}

/// Map CLI argument errors to human-readable messages.
pub fn cliArgErrorMessage(err: cli.ArgError) []const u8 {
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

/// Print available generators to stderr.
fn printAvailableGenerators() void {
    std.debug.print("Available generators:\n", .{});
    for (generator.REGISTRY) |gen| {
        std.debug.print("  {s}\n", .{gen.name});
    }
}

/// Handle CLI argument parsing errors — prints message and exits.
pub fn handleParseError(err: anyerror, arg_list: []const []const u8) noreturn {
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

/// Handle dispatch errors — prints message and exits.
pub fn handleDispatchError(err: anyerror, parsed: cli.ParsedArgs) noreturn {
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
        error.GeneratorHealthCheckFailed => {
            // Error message already printed by handler
            std.process.exit(1);
        },
        error.StrictWarnings => {
            if (!parsed.quiet) {
                fmt.printErr("lint strict mode: found warnings");
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

// ─── Tests ─────────────────────────────────────────────────────

const testing = std.testing;

test "getInputPaths: compile command" {
    const cmd = cli.Command{ .compile = .{ .input = "schema.ss", .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } };
    const paths = getInputPaths(cmd);
    try testing.expectEqualStrings("schema.ss", paths.path1.?);
    try testing.expect(paths.path2 == null);
}

test "getInputPaths: diff command" {
    const cmd = cli.Command{ .diff = .{ .old = "old.ss", .new = "new.ss", .trace = false, .stats = false, .format = .text, .check = false } };
    const paths = getInputPaths(cmd);
    try testing.expectEqualStrings("old.ss", paths.path1.?);
    try testing.expectEqualStrings("new.ss", paths.path2.?);
}

test "getInputPaths: version command" {
    const cmd = cli.Command{ .version = .{ .json = false } };
    const paths = getInputPaths(cmd);
    try testing.expect(paths.path1 == null);
    try testing.expect(paths.path2 == null);
}

test "cliArgErrorMessage: UnknownDialect" {
    const msg = cliArgErrorMessage(error.UnknownDialect);
    try testing.expect(msg.len > 0);
    try testing.expect(std.mem.indexOf(u8, msg, "dialect") != null);
}

test "cliArgErrorMessage: all error variants produce messages" {
    const errors = [_]cli.ArgError{
        error.UnknownDialect,
        error.MissingDialectValue,
        error.UnknownTarget,
        error.MissingTargetValue,
        error.UnknownFormat,
        error.MissingFormatValue,
        error.MissingConfigValue,
        error.MissingImportPathValue,
        error.DiffMissingArgs,
        error.MigrateMissingArgs,
        error.MissingArgs,
        error.UnknownCommand,
        error.UnknownFlag,
        error.UnknownGenerator,
        error.UnknownShell,
        error.UnknownHookType,
    };
    for (errors) |err| {
        const msg = cliArgErrorMessage(err);
        try testing.expect(msg.len > 0);
    }
}
