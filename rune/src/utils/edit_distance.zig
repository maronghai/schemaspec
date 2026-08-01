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
