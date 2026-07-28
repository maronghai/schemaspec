const std = @import("std");
const parse_check = @import("parse_check.zig");
const CheckKind = @import("../types/ast.zig").CheckKind;

test "classifyCheck: range [1, 100]" {
    try std.testing.expectEqual(CheckKind.range, parse_check.classifyCheck("1, 100", '[', ']'));
}

test "classifyCheck: range_upper_exclusive [1, 100)" {
    try std.testing.expectEqual(CheckKind.range_upper_exclusive, parse_check.classifyCheck("1, 100", '[', ')'));
}

test "classifyCheck: range_lower_exclusive (1, 100]" {
    try std.testing.expectEqual(CheckKind.range_lower_exclusive, parse_check.classifyCheck("1, 100", '(', ']'));
}

test "classifyCheck: range_both_exclusive (1, 100)" {
    try std.testing.expectEqual(CheckKind.range_both_exclusive, parse_check.classifyCheck("1, 100", '(', ')'));
}

test "classifyCheck: in_list {active, inactive}" {
    try std.testing.expectEqual(CheckKind.in_list, parse_check.classifyCheck("active, inactive", '{', '}'));
}

test "classifyCheck: comparison {price > 0}" {
    try std.testing.expectEqual(CheckKind.comparison, parse_check.classifyCheck("price > 0", '{', '}'));
}

test "classifyCheck: comparison with AND" {
    try std.testing.expectEqual(CheckKind.comparison, parse_check.classifyCheck("price > 0 AND price < 10000", '[', ']'));
}

test "classifyCheck: single value → comparison" {
    try std.testing.expectEqual(CheckKind.comparison, parse_check.classifyCheck("active", '{', '}'));
}

test "parseCheckConstraint: returns null for non-bracket token" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{"hello"};
    const result = try parse_check.parseCheckConstraint(alloc, &tokens, 0, "", 1);
    try std.testing.expect(result == null);
}

test "parseCheckConstraint: bracket token" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "[", "1, 100", "]" };
    const result = try parse_check.parseCheckConstraint(alloc, &tokens, 0, "", 1);
    try std.testing.expect(result != null);
    const r = result.?;
    try std.testing.expectEqual(CheckKind.range, r.check.kind);
    try std.testing.expectEqualStrings("1, 100", r.check.expr);
    try std.testing.expectEqual(@as(usize, 3), r.end_idx);
    alloc.free(r.check.expr);
}
