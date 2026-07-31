const std = @import("std");
const check = @import("check.zig");

const testing = std.testing;
const reverseCheck = check.reverseCheck;

// ─── Unit Tests ──────────────────────────────────────────────

test "reverseCheck BETWEEN" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "age BETWEEN 0 AND 150", "age");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("[0,150]", result.?);
}

test "reverseCheck IN list" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "status IN ('active', 'pending')", "status");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("{active,pending}", result.?);
}

test "reverseCheck >= comparison" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "age >= 18", "age");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("{>=18}", result.?);
}

test "reverseCheck upper exclusive range" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "price >= 10 AND price < 100", "price");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("[10,100)", result.?);
}

test "reverseCheck lower exclusive range" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "score > 0 AND score <= 100", "score");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("(0,100]", result.?);
}

test "reverseCheck no match → null" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "x = 1", "y");
    try testing.expect(result == null);
}

test "reverseCheck both exclusive range" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "score > 0 AND score < 100", "score");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("(0,100)", result.?);
}

test "reverseCheck compound comparison >= AND <=" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "age >= 18 AND age <= 65", "age");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("{>=18,<=65}", result.?);
}

test "reverseCheck single comparison =" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "status = 1", "status");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("{=1}", result.?);
}

test "reverseCheck single comparison <" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "count < 10", "count");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("{<10}", result.?);
}

test "reverseCheck backtick-quoted column" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "`age` BETWEEN 0 AND 150", "age");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("[0,150]", result.?);
}

test "reverseCheck double-quote-quoted column" {
    const alloc = testing.allocator;
    const result = reverseCheck(alloc, "\"age\" BETWEEN 0 AND 150", "age");
    try testing.expect(result != null);
    defer alloc.free(result.?);
    try testing.expectEqualStrings("[0,150]", result.?);
}
