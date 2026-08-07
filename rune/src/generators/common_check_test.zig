const std = @import("std");
const common_check = @import("common_check.zig");

test "parseRange: >= and <=" {
    const result = common_check.parseRange(">=0 AND <=100");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(?i64, 0), r.min);
        try std.testing.expectEqual(@as(?i64, 100), r.max);
    }
}

test "parseRange: >= only" {
    const result = common_check.parseRange(">=18");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(?i64, 18), r.min);
        try std.testing.expect(r.max == null);
    }
}

test "parseRange: <= only" {
    const result = common_check.parseRange("<=255");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expect(r.min == null);
        try std.testing.expectEqual(@as(?i64, 255), r.max);
    }
}

test "parseRange: negative numbers" {
    const result = common_check.parseRange(">=-10 AND <=10");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(?i64, -10), r.min);
        try std.testing.expectEqual(@as(?i64, 10), r.max);
    }
}

test "parseRange: no range" {
    const result = common_check.parseRange("LIKE 'foo%'");
    try std.testing.expect(result == null);
}

test "parseComparison: >=" {
    const result = common_check.parseComparison(">= 0");
    try std.testing.expect(result != null);
    if (result) |c| {
        try std.testing.expectEqualStrings(">=", c.op);
        try std.testing.expectEqual(@as(i64, 0), c.value);
    }
}

test "parseComparison: =" {
    const result = common_check.parseComparison("= 42");
    try std.testing.expect(result != null);
    if (result) |c| {
        try std.testing.expectEqualStrings("=", c.op);
        try std.testing.expectEqual(@as(i64, 42), c.value);
    }
}

test "parseComparison: <" {
    const result = common_check.parseComparison("< 100");
    try std.testing.expect(result != null);
    if (result) |c| {
        try std.testing.expectEqualStrings("<", c.op);
        try std.testing.expectEqual(@as(i64, 100), c.value);
    }
}

test "parseComparison: negative" {
    const result = common_check.parseComparison(">= -5");
    try std.testing.expect(result != null);
    if (result) |c| {
        try std.testing.expectEqual(@as(i64, -5), c.value);
    }
}

test "parseComparison: no match" {
    const result = common_check.parseComparison("LIKE '%foo%'");
    try std.testing.expect(result == null);
}

test "parseInList: quoted values" {
    const result = common_check.parseInList(std.testing.allocator, "('active', 'inactive', 'pending')");
    defer if (result) |r| std.testing.allocator.free(r);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(usize, 3), r.len);
        try std.testing.expectEqualStrings("active", r[0]);
        try std.testing.expectEqualStrings("inactive", r[1]);
        try std.testing.expectEqualStrings("pending", r[2]);
    }
}

test "parseInList: unquoted values" {
    const result = common_check.parseInList(std.testing.allocator, "(1, 2, 3)");
    defer if (result) |r| std.testing.allocator.free(r);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(usize, 3), r.len);
        try std.testing.expectEqualStrings("1", r[0]);
    }
}

test "parseInList: empty" {
    const result = common_check.parseInList(std.testing.allocator, "()");
    try std.testing.expect(result == null);
}

test "parseInList: single value" {
    const result = common_check.parseInList(std.testing.allocator, "('only')");
    defer if (result) |r| std.testing.allocator.free(r);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(usize, 1), r.len);
        try std.testing.expectEqualStrings("only", r[0]);
    }
}
