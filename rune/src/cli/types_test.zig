const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

test "Command: compile default values" {
    const cmd = types.Command{ .compile = .{ .input = null, .output = null, .trace = false, .stats = false, .check = false, .verbose_passes = false } };
    try testing.expectEqual(@as(?[]const u8, null), cmd.compile.input);
    try testing.expectEqual(@as(?[]const u8, null), cmd.compile.output);
    try testing.expectEqual(false, cmd.compile.trace);
    try testing.expectEqual(false, cmd.compile.stream);
    try testing.expectEqual(false, cmd.compile.parallel);
}

test "Command: diff struct fields" {
    const cmd = types.Command{ .diff = .{ .old = "old.ss", .new = "new.ss", .trace = false, .stats = false, .format = .text, .check = false } };
    try testing.expectEqualStrings("old.ss", cmd.diff.old);
    try testing.expectEqualStrings("new.ss", cmd.diff.new);
    try testing.expectEqual(false, cmd.diff.summary);
    try testing.expectEqual(@as(?[]const u8, null), cmd.diff.from_sql);
}

test "Command: migrate struct fields" {
    const cmd = types.Command{ .migrate = .{ .old = "old.ss", .new = "new.ss", .output = null, .trace = false, .rollback = false, .stats = false, .dry_run = false, .format = .text, .check = false, .name = null, .dir = null, .incremental = false } };
    try testing.expectEqual(false, cmd.migrate.graph);
    try testing.expectEqual(false, cmd.migrate.no_lint);
}

test "Command: lint default values" {
    const cmd = types.Command{ .lint = .{} };
    try testing.expectEqual(@as(?[]const u8, null), cmd.lint.input);
    try testing.expectEqual(false, cmd.lint.json_errors);
    try testing.expectEqual(false, cmd.lint.strict);
    try testing.expectEqual(types.LintFormat.text, cmd.lint.format);
    try testing.expectEqual(false, cmd.lint.fix);
    try testing.expectEqual(false, cmd.lint.dry_run);
    try testing.expectEqual(false, cmd.lint.show_rules);
    try testing.expectEqual(false, cmd.lint.init_config);
}

test "COMMAND_REGISTRY has all commands" {
    // Should have at least 16 commands
    try testing.expect(types.COMMAND_REGISTRY.len >= 16);
}
