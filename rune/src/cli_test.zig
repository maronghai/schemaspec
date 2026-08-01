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
    const args = makeArgs(3, .{ "rune", "-d", "db2" });
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
