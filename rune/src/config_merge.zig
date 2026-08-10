const std = @import("std");
const cli = @import("cli.zig");
const config_mod = @import("config.zig");
const dialect_enum = @import("dialect/enum.zig");

// ─── Config Merge ──────────────────────────────────────────────
// Extracted from main.zig for testability and reuse.
// Merges CLI flags with config file defaults (CLI takes precedence).

/// Merge config file defaults into parsed CLI args.
/// CLI flags take precedence over config file values.
pub fn mergeCliConfig(
    parsed: *cli.ParsedArgs,
    cfg: config_mod.Config,
) void {
    // Dialect: config file sets default when CLI flag not explicit
    if (!parsed.dialect_was_explicit and cfg.dialect != null) {
        parsed.dialect = cli.parseDialect(cfg.dialect.?) catch parsed.dialect;
    }

    // Quiet: config file sets when CLI doesn't
    if (cfg.quiet != null and !parsed.quiet) {
        parsed.quiet = cfg.quiet.?;
    }

    // JSON errors: config file sets when CLI doesn't
    if (cfg.json_errors != null and !parsed.json_errors) {
        parsed.json_errors = cfg.json_errors.?;
    }

    // Color: config file overrides with "always"/"never" parsing
    if (cfg.color != null) {
        parsed.color = if (std.mem.eql(u8, cfg.color.?, "always"))
            .always
        else if (std.mem.eql(u8, cfg.color.?, "never"))
            .never
        else
            parsed.color;
    }

    // Target: config file sets default when CLI flag not explicit
    if (cfg.target != null and !parsed.dialect_was_explicit) {
        parsed.target = cli.parseTarget(cfg.target.?) catch parsed.target;
    }

    // Stream: config file sets for compile command
    if (cfg.stream != null and parsed.command == .compile) {
        parsed.command.compile.stream = parsed.command.compile.stream or cfg.stream.?;
    }

    // Parallel: config file sets for compile and watch commands
    if (cfg.parallel != null) {
        if (parsed.command == .compile) {
            parsed.command.compile.parallel = parsed.command.compile.parallel or cfg.parallel.?;
        } else if (parsed.command == .watch) {
            parsed.command.watch.parallel = parsed.command.watch.parallel or cfg.parallel.?;
        }
    }
}

// ─── Tests ─────────────────────────────────────────────────────

test "mergeCliConfig dialect from config" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };
    parsed.dialect_was_explicit = false;

    const cfg = config_mod.Config{
        .dialect = "pg",
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expectEqual(dialect_enum.Dialect.pg, parsed.dialect);
}

test "mergeCliConfig dialect CLI precedence" {
    var parsed = cli.ParsedArgs{
        .dialect = .sqlite,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };
    parsed.dialect_was_explicit = true;

    const cfg = config_mod.Config{
        .dialect = "pg",
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expectEqual(dialect_enum.Dialect.sqlite, parsed.dialect);
}

test "mergeCliConfig quiet from config" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .quiet = true,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.quiet);
}

test "mergeCliConfig quiet CLI precedence" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = true,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .quiet = false,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.quiet);
}

test "mergeCliConfig json_errors from config" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .json_errors = true,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.json_errors);
}

test "mergeCliConfig color always" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .color = "always",
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expectEqual(.always, parsed.color);
}

test "mergeCliConfig color never" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .color = "never",
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expectEqual(.never, parsed.color);
}

test "mergeCliConfig color invalid keeps default" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .color = "invalid",
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expectEqual(.auto, parsed.color);
}

test "mergeCliConfig stream for compile" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .stream = true,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.command.compile.stream);
}

test "mergeCliConfig parallel for compile" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .parallel = true,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.command.compile.parallel);
}

test "mergeCliConfig parallel for watch" {
    var parsed = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .{ .watch = .{ .input = "test.ss" } },
        .quiet = false,
        .strict = false,
    };

    const cfg = config_mod.Config{
        .parallel = true,
    };

    mergeCliConfig(&parsed, cfg);
    try std.testing.expect(parsed.command.watch.parallel);
}
