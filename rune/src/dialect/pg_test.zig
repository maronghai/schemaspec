const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "pg: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.pg);

    // int → integer
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("integer", result);
    }
    // blob → bytea
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bytea", result);
    }
    // decimal → numeric(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("numeric(10, 2)", result);
    }
    // boolean
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("boolean", result);
    }
    // timestamptz
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .timestamptz);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("timestamptz", result);
    }
}

test "pg: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.pg).quoteChar);
}
