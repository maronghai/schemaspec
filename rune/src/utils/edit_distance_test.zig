const std = @import("std");
const edit_distance = @import("edit_distance.zig");

const distance = edit_distance.distance;
const suggestClosest = edit_distance.suggestClosest;
const testing = std.testing;

test "edit_distance: identical strings" {
    try testing.expectEqual(@as(usize, 0), distance("hello", "hello"));
}

test "edit_distance: empty strings" {
    try testing.expectEqual(@as(usize, 0), distance("", ""));
    try testing.expectEqual(@as(usize, 5), distance("hello", ""));
    try testing.expectEqual(@as(usize, 5), distance("", "hello"));
}

test "edit_distance: single substitution" {
    try testing.expectEqual(@as(usize, 1), distance("cat", "bat"));
}

test "edit_distance: single insertion" {
    try testing.expectEqual(@as(usize, 1), distance("cat", "cats"));
}

test "edit_distance: single deletion" {
    try testing.expectEqual(@as(usize, 1), distance("cats", "cat"));
}

test "edit_distance: multiple edits" {
    try testing.expectEqual(@as(usize, 3), distance("kitten", "sitting"));
}

test "edit_distance: completely different" {
    try testing.expectEqual(@as(usize, 5), distance("abcde", "fghij"));
}

test "suggest_closest: exact match returns distance 0" {
    const candidates = [_][]const u8{ "users", "orders", "products" };
    const result = suggestClosest("users", &candidates, 3);
    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 0), result.?.distance);
}

test "suggest_closest: close match within threshold" {
    const candidates = [_][]const u8{ "users", "orders", "products" };
    const result = suggestClosest("user", &candidates, 2);
    try testing.expect(result != null);
    try testing.expect(std.mem.eql(u8, result.?.match, "users"));
}

test "suggest_closest: no match beyond threshold" {
    const candidates = [_][]const u8{ "users", "orders", "products" };
    const result = suggestClosest("xyz", &candidates, 1);
    try testing.expect(result == null);
}

test "suggest_closest: empty candidates" {
    const candidates = [_][]const u8{};
    const result = suggestClosest("users", &candidates, 3);
    try testing.expect(result == null);
}
