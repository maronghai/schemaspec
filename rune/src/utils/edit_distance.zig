const std = @import("std");

/// Levenshtein edit distance between two strings.
/// Returns the minimum number of single-character edits (insertions, deletions, substitutions)
/// required to change `a` into `b`. O(a.len * b.len) time, O(min(a.len, b.len)) space.
/// Uses stack-allocated arrays (max 256) — suitable for table/column names.
pub fn distance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Use the smaller string for the space dimension
    const short = if (a.len <= b.len) a else b;
    const long = if (a.len <= b.len) b else a;

    // Stack-allocated DP rows (256 is well above typical identifier lengths)
    const max_len = @min(short.len + 1, 256);
    var prev: [256]usize = undefined;
    var curr: [256]usize = undefined;

    for (0..max_len) |i| {
        prev[i] = i;
    }

    for (1..long.len + 1) |i| {
        curr[0] = i;
        for (1..max_len) |j| {
            const cost: usize = if (long[i - 1] == short[j - 1]) 0 else 1;
            const del = prev[j] + 1;
            const ins = curr[j - 1] + 1;
            const sub = prev[j - 1] + cost;
            curr[j] = @min(del, @min(ins, sub));
        }
        std.mem.swap([256]usize, &prev, &curr);
    }

    return prev[short.len];
}

/// Result of a suggestion lookup.
pub const Suggestion = struct {
    match: []const u8,
    distance: usize,
};

/// Find the closest match for `target` in `candidates`.
/// Returns the best match if its distance is <= `max_distance`, otherwise null.
pub fn suggestClosest(target: []const u8, candidates: []const []const u8, max_distance: usize) ?Suggestion {
    var best_match: ?[]const u8 = null;
    var best_distance: usize = max_distance + 1;

    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate, target)) return .{ .match = candidate, .distance = 0 };
        const d = distance(target, candidate);
        if (d < best_distance) {
            best_distance = d;
            best_match = candidate;
        }
    }

    if (best_match) |m| {
        if (best_distance <= max_distance) return .{ .match = m, .distance = best_distance };
    }
    return null;
}

// ─── Unit Tests ──────────────────────────────────────────────

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
