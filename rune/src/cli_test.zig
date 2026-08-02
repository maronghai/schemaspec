const std = @import("std");
const cli = @import("cli.zig");
const Command = cli.Command;
const dialect_enum = @import("dialect/enum.zig");

const testing = std.testing;

fn makeArgs(comptime n: usize, args: [n][]const u8) [n][]const u8 {
    return args;
}

test "parseArgs: --version returns version command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "--version" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(Command.version, result.command);
}

test "parseArgs: -v returns version command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "-v" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(Command.version, result.command);
}

test "parseArgs: compile with input file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.input != null);
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: compile with -o flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(4, .{ "rune", "schema.ss", "-o", "out.sql" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.output != null);
            try testing.expectEqualStrings("out.sql", cmd.output.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --dialect pg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "--dialect", "pg" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(dialect_enum.Dialect.pg, result.dialect);
}

test "parseArgs: -d sqlite" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "-d", "sqlite" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(dialect_enum.Dialect.sqlite, result.dialect);
}

test "parseArgs: unknown dialect returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "-d", "db9" });
    try testing.expectError(error.UnknownDialect, cli.parseArgs(alloc, &args));
}

test "parseArgs: missing dialect value returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "-d" });
    try testing.expectError(error.MissingDialectValue, cli.parseArgs(alloc, &args));
}

test "parseArgs: diff with two files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(4, .{ "rune", "diff", "old.ss", "new.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .diff => |cmd| {
            try testing.expectEqualStrings("old.ss", cmd.old);
            try testing.expectEqualStrings("new.ss", cmd.new);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: diff missing args returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "diff" });
    try testing.expectError(error.DiffMissingArgs, cli.parseArgs(alloc, &args));
}

test "parseArgs: migrate missing args returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "migrate" });
    try testing.expectError(error.MigrateMissingArgs, cli.parseArgs(alloc, &args));
}

test "parseArgs: migrate with --rollback" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(5, .{ "rune", "migrate", "old.ss", "new.ss", "--rollback" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .migrate => |cmd| {
            try testing.expect(cmd.rollback);
            try testing.expectEqualStrings("old.ss", cmd.old);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: reverse with -T flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "reverse", "-T" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .reverse => |cmd| {
            try testing.expect(cmd.with_templates);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: validate with input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "validate", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .validate => |cmd| {
            try testing.expect(cmd.input != null);
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: no args returns compile with null input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(1, .{"rune"});
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.input == null);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: default dialect is mysql" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(1, .{"rune"});
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(dialect_enum.Dialect.mysql, result.dialect);
}

test "parseArgs: postgres alias resolves to pg dialect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "-d", "postgres" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(dialect_enum.Dialect.pg, result.dialect);
}

test "parseArgs: --help returns help command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "--help" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(Command.help, result.command);
}

test "parseArgs: -h returns help command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "-h" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(Command.help, result.command);
}

test "parseArgs: --stats flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--stats" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.stats);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: -s short flag for stats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "-s" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.stats);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --quiet flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--quiet" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expect(result.quiet);
}

test "parseArgs: -q short flag for quiet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "-q" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expect(result.quiet);
}

test "parseArgs: --check flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--check" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.check);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: diff --stats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(5, .{ "rune", "diff", "old.ss", "new.ss", "--stats" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .diff => |cmd| {
            try testing.expect(cmd.stats);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: migrate --stats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(5, .{ "rune", "migrate", "old.ss", "new.ss", "--stats" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .migrate => |cmd| {
            try testing.expect(cmd.stats);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: reverse --stats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(4, .{ "rune", "reverse", "schema.sql", "--stats" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .reverse => |cmd| {
            try testing.expect(cmd.stats);
        },
        else => try testing.expect(false),
    }
}

// ─── New tests for v0.82.0 ────────────────────────────────────

test "parseArgs: --format sarif for diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(6, .{ "rune", "diff", "old.ss", "new.ss", "--format", "sarif" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .diff => |cmd| {
            try testing.expectEqual(cli.DiffFormat.sarif, cmd.format);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --format json for diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(6, .{ "rune", "diff", "old.ss", "new.ss", "--format", "json" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .diff => |cmd| {
            try testing.expectEqual(cli.DiffFormat.json, cmd.format);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: unknown format returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(6, .{ "rune", "diff", "old.ss", "new.ss", "--format", "xml" });
    try testing.expectError(error.UnknownFormat, cli.parseArgs(alloc, &args));
}

test "parseArgs: generate prisma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(4, .{ "rune", "generate", "prisma", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .generate => |cmd| {
            try testing.expectEqualStrings("prisma", cmd.generator);
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
            try testing.expect(!cmd.list);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: generate --list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "generate", "--list" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .generate => |cmd| {
            try testing.expect(cmd.list);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: docs command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "docs", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .docs => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: format command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "format", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .format_cmd => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: init command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "init", "myapp" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .init => |cmd| {
            try testing.expectEqualStrings("myapp", cmd.name.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: init without name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "init" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .init => |cmd| {
            try testing.expect(cmd.name == null);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: completions command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "completions", "zsh" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .completions => |cmd| {
            try testing.expectEqualStrings("zsh", cmd.shell);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: completions default bash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(2, .{ "rune", "completions" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .completions => |cmd| {
            try testing.expectEqualStrings("bash", cmd.shell);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: check command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "check", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .check => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: stats command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "stats", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .stats => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --strict flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--strict" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expect(result.strict);
}

test "parseArgs: --json-errors flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--json-errors" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expect(result.json_errors);
}

test "parseArgs: --verbose-passes flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "schema.ss", "--verbose-passes" });
    const result = try cli.parseArgs(alloc, &args);
    switch (result.command) {
        .compile => |cmd| {
            try testing.expect(cmd.verbose_passes);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --target json-schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(4, .{ "rune", "--target", "json-schema", "schema.ss" });
    const result = try cli.parseArgs(alloc, &args);
    try testing.expectEqual(cli.Target.json_schema, result.target);
}

test "parseArgs: unknown long flag returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = makeArgs(3, .{ "rune", "--bogus", "schema.ss" });
    try testing.expectError(error.UnknownFlag, cli.parseArgs(alloc, &args));
}

test "findUnknownFlag: returns flag name" {
    const flag = cli.findUnknownFlag(&[_][]const u8{ "rune", "--bogus", "schema.ss" });
    try testing.expect(flag != null);
    try testing.expectEqualStrings("--bogus", flag.?);
}

test "findUnknownFlag: returns null for known flags" {
    const flag = cli.findUnknownFlag(&[_][]const u8{ "rune", "--version" });
    try testing.expect(flag == null);
}

test "findUnknownFlag: returns null for no flags" {
    const flag = cli.findUnknownFlag(&[_][]const u8{ "rune", "schema.ss" });
    try testing.expect(flag == null);
}
