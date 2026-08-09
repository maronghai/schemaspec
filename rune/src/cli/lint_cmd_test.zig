const std = @import("std");
const testing = std.testing;
const lint_cmd = @import("lint_cmd.zig");
const LintCmd = lint_cmd.LintCmd;
const LintFormat = @import("../cli/types.zig").LintFormat;

test "LintCmd: default values" {
    const cmd = LintCmd{};
    try testing.expectEqual(@as(?[]const u8, null), cmd.input);
    try testing.expectEqual(@as(?[]const u8, null), cmd.input2);
    try testing.expectEqual(false, cmd.json_errors);
    try testing.expectEqual(false, cmd.strict);
    try testing.expectEqual(LintFormat.text, cmd.format);
    try testing.expectEqual(@as(?[]const u8, null), cmd.rules);
    try testing.expectEqual(false, cmd.fix);
    try testing.expectEqual(false, cmd.dry_run);
}

test "LintCmd: custom values" {
    const cmd = LintCmd{
        .input = "schema.ss",
        .input2 = "other.ss",
        .json_errors = true,
        .strict = true,
        .format = .sarif,
        .rules = "lint.toml",
        .fix = true,
        .dry_run = true,
    };
    try testing.expectEqualStrings("schema.ss", cmd.input.?);
    try testing.expectEqualStrings("other.ss", cmd.input2.?);
    try testing.expectEqual(true, cmd.json_errors);
    try testing.expectEqual(true, cmd.strict);
    try testing.expectEqual(LintFormat.sarif, cmd.format);
    try testing.expectEqualStrings("lint.toml", cmd.rules.?);
    try testing.expectEqual(true, cmd.fix);
    try testing.expectEqual(true, cmd.dry_run);
}

test "LintCmd: partial values" {
    const cmd = LintCmd{
        .input = "test.ss",
        .strict = true,
    };
    try testing.expectEqualStrings("test.ss", cmd.input.?);
    try testing.expectEqual(@as(?[]const u8, null), cmd.input2);
    try testing.expectEqual(false, cmd.json_errors);
    try testing.expectEqual(true, cmd.strict);
    try testing.expectEqual(LintFormat.text, cmd.format);
    try testing.expectEqual(@as(?[]const u8, null), cmd.rules);
    try testing.expectEqual(false, cmd.fix);
    try testing.expectEqual(false, cmd.dry_run);
}
