const std = @import("std");
const build_options = @import("build_options");

/// Rune version constant. Single source of truth for all modules.
/// Injected from build.zig.zon at compile time via build_options.
pub const VERSION = build_options.VERSION;

// ─── Structured Version ──────────────────────────────────────

/// Semantic version with major, minor, patch components.
/// Supports parsing from string, formatting back, and comparison.
pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,

    /// Parse a version string like "0.219.0" into a Version struct.
    /// Ignores leading/trailing whitespace and any suffix after the patch number.
    pub fn parse(str: []const u8) Version {
        var v = Version{ .major = 0, .minor = 0, .patch = 0 };
        var i: usize = 0;

        // Skip leading whitespace
        while (i < str.len and str[i] == ' ') i += 1;

        // Parse major
        while (i < str.len and str[i] >= '0' and str[i] <= '9') {
            v.major = v.major * 10 + (str[i] - '0');
            i += 1;
        }
        if (i < str.len and str[i] == '.') i += 1;

        // Parse minor
        while (i < str.len and str[i] >= '0' and str[i] <= '9') {
            v.minor = v.minor * 10 + (str[i] - '0');
            i += 1;
        }
        if (i < str.len and str[i] == '.') i += 1;

        // Parse patch
        while (i < str.len and str[i] >= '0' and str[i] <= '9') {
            v.patch = v.patch * 10 + (str[i] - '0');
            i += 1;
        }

        return v;
    }

    /// Format version back to "major.minor.patch" string.
    pub fn format(self: Version, writer: *std.Io.Writer) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }

    /// Format version to an allocated string "major.minor.patch".
    /// Caller owns the returned memory.
    pub fn formatAlloc(self: Version, alloc: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(alloc, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }

    /// Write "major.minor" to the provided writer (e.g. "0.238").
    /// Useful for docs references without patch number.
    pub fn writeMajorMinor(self: Version, writer: *std.Io.Writer) !void {
        try writer.print("{d}.{d}", .{ self.major, self.minor });
    }

    /// Compare two versions. Returns ordering.
    pub fn order(self: Version, other: Version) std.math.Order {
        if (self.major != other.major) return if (self.major < other.major) .lt else .gt;
        if (self.minor != other.minor) return if (self.minor < other.minor) .lt else .gt;
        if (self.patch != other.patch) return if (self.patch < other.patch) .lt else .gt;
        return .eq;
    }

    /// Greater than or equal.
    pub fn gte(self: Version, other: Version) bool {
        return self.order(other) != .lt;
    }

    /// Less than or equal.
    pub fn lte(self: Version, other: Version) bool {
        return self.order(other) != .gt;
    }

    /// Greater than.
    pub fn gt(self: Version, other: Version) bool {
        return self.order(other) == .gt;
    }

    /// Less than.
    pub fn lt(self: Version, other: Version) bool {
        return self.order(other) == .lt;
    }

    /// Equal.
    pub fn eq(self: Version, other: Version) bool {
        return self.order(other) == .eq;
    }
};

/// Parse the compile-time VERSION string into a Version struct.
pub const CURRENT: Version = Version.parse(VERSION);

// ─── Output ──────────────────────────────────────────────────

/// Print version to stderr.
pub fn printVersion() void {
    std.debug.print("rune {s}\n", .{VERSION});
}

/// Print version as JSON to stderr.
pub fn printVersionJson() void {
    std.debug.print("{{\"version\":\"{s}\",\"binary\":\"rune\"}}\n", .{VERSION});
}

// ─── Tests ──────────────────────────────────────────────────

test "Version.parse: basic" {
    const v = Version.parse("0.219.0");
    try std.testing.expectEqual(@as(u16, 0), v.major);
    try std.testing.expectEqual(@as(u16, 219), v.minor);
    try std.testing.expectEqual(@as(u16, 0), v.patch);
}

test "Version.parse: with whitespace" {
    const v = Version.parse("  1.2.3  ");
    try std.testing.expectEqual(@as(u16, 1), v.major);
    try std.testing.expectEqual(@as(u16, 2), v.minor);
    try std.testing.expectEqual(@as(u16, 3), v.patch);
}

test "Version.parse: large numbers" {
    const v = Version.parse("10.200.999");
    try std.testing.expectEqual(@as(u16, 10), v.major);
    try std.testing.expectEqual(@as(u16, 200), v.minor);
    try std.testing.expectEqual(@as(u16, 999), v.patch);
}

test "Version.parse: zero" {
    const v = Version.parse("0.0.0");
    try std.testing.expectEqual(@as(u16, 0), v.major);
    try std.testing.expectEqual(@as(u16, 0), v.minor);
    try std.testing.expectEqual(@as(u16, 0), v.patch);
}

test "Version.parse: ignores suffix" {
    const v = Version.parse("1.2.3-beta.1");
    try std.testing.expectEqual(@as(u16, 1), v.major);
    try std.testing.expectEqual(@as(u16, 2), v.minor);
    try std.testing.expectEqual(@as(u16, 3), v.patch);
}

test "Version.parse: CURRENT matches VERSION" {
    try std.testing.expect(CURRENT.major == 0);
    // CURRENT is parsed from the compile-time VERSION string
    try std.testing.expect(CURRENT.minor > 0);
}

test "Version.order: equal" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 3 };
    try std.testing.expectEqual(std.math.Order.eq, a.order(b));
}

test "Version.order: major differs" {
    const a = Version{ .major = 1, .minor = 0, .patch = 0 };
    const b = Version{ .major = 2, .minor = 0, .patch = 0 };
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
    try std.testing.expectEqual(std.math.Order.gt, b.order(a));
}

test "Version.order: minor differs" {
    const a = Version{ .major = 1, .minor = 1, .patch = 0 };
    const b = Version{ .major = 1, .minor = 2, .patch = 0 };
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

test "Version.order: patch differs" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 4 };
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

test "Version comparisons: gte" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 3 };
    const c = Version{ .major = 1, .minor = 2, .patch = 4 };
    try std.testing.expect(a.gte(b));
    try std.testing.expect(a.gte(a));
    try std.testing.expect(!a.gte(c));
}

test "Version comparisons: lte" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 3 };
    const c = Version{ .major = 1, .minor = 2, .patch = 2 };
    try std.testing.expect(a.lte(b));
    try std.testing.expect(a.lte(a));
    try std.testing.expect(!a.lte(c));
}

test "Version comparisons: gt and lt" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 4 };
    try std.testing.expect(b.gt(a));
    try std.testing.expect(a.lt(b));
    try std.testing.expect(!a.gt(b));
    try std.testing.expect(!b.lt(a));
}

test "Version comparisons: eq" {
    const a = Version{ .major = 1, .minor = 2, .patch = 3 };
    const b = Version{ .major = 1, .minor = 2, .patch = 3 };
    const c = Version{ .major = 1, .minor = 2, .patch = 4 };
    try std.testing.expect(a.eq(b));
    try std.testing.expect(!a.eq(c));
}

// ─── formatAlloc Tests ───────────────────────────────────────

test "formatAlloc: basic version" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const v = Version{ .major = 0, .minor = 238, .patch = 0 };
    const str = try v.formatAlloc(alloc);
    try std.testing.expectEqualStrings("0.238.0", str);
}

test "formatAlloc: large version" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const v = Version{ .major = 10, .minor = 200, .patch = 999 };
    const str = try v.formatAlloc(alloc);
    try std.testing.expectEqualStrings("10.200.999", str);
}

test "formatAlloc: zero version" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const v = Version{ .major = 0, .minor = 0, .patch = 0 };
    const str = try v.formatAlloc(alloc);
    try std.testing.expectEqualStrings("0.0.0", str);
}

// ─── Additional Parse Edge Cases ─────────────────────────────

test "Version.parse: single digit" {
    const v = Version.parse("1.2.3");
    try std.testing.expectEqual(@as(u16, 1), v.major);
    try std.testing.expectEqual(@as(u16, 2), v.minor);
    try std.testing.expectEqual(@as(u16, 3), v.patch);
}

test "Version.parse: no patch" {
    const v = Version.parse("0.238");
    try std.testing.expectEqual(@as(u16, 0), v.major);
    try std.testing.expectEqual(@as(u16, 238), v.minor);
    try std.testing.expectEqual(@as(u16, 0), v.patch);
}
