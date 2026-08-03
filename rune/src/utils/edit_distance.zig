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

/// Runtime Levenshtein edit distance for arbitrary byte slices.
pub fn runtimeEditDistance(a: []const u8, b: []const u8) usize {
    const m = a.len;
    const n = b.len;
    if (m == 0) return n;
    if (n == 0) return m;
    // Use arena for temp allocation (callers are command-lifetime)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var prev = alloc.alloc(usize, n + 1) catch return m + n;
    var curr = alloc.alloc(usize, n + 1) catch return m + n;
    var i: usize = 0;
    while (i <= n) : (i += 1) {
        prev[i] = i;
    }
    i = 1;
    while (i <= m) : (i += 1) {
        curr[0] = i;
        var j: usize = 1;
        while (j <= n) : (j += 1) {
            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
            const del = prev[j] + 1;
            const ins = curr[j - 1] + 1;
            const sub = prev[j - 1] + cost;
            curr[j] = @min(@min(del, ins), sub);
        }
        const tmp = prev.ptr;
        prev.ptr = curr.ptr;
        curr.ptr = tmp;
    }
    return prev[n];
}

test "runtimeEditDistance: identical" {
    try std.testing.expectEqual(@as(usize, 0), runtimeEditDistance("hello", "hello"));
}

test "runtimeEditDistance: empty" {
    try std.testing.expectEqual(@as(usize, 5), runtimeEditDistance("hello", ""));
    try std.testing.expectEqual(@as(usize, 5), runtimeEditDistance("", "hello"));
}

test "runtimeEditDistance: single char" {
    try std.testing.expectEqual(@as(usize, 1), runtimeEditDistance("hello", "hallo"));
}
