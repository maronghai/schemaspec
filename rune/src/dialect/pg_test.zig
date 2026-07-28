const std = @import("std");
const pg = @import("pg.zig");
const dialect = @import("dialect.zig");

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "pg: renderType maps common types" {
    const alloc = testing.allocator;

    // int → integer
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try pg.pgRenderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("integer", result);
    }
    // blob → bytea
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try pg.pgRenderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bytea", result);
    }
    // decimal → numeric(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try pg.pgRenderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("numeric(10, 2)", result);
    }
    // boolean
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try pg.pgRenderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("boolean", result);
    }
    // timestamptz
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try pg.pgRenderType(w, .timestamptz);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("timestamptz", result);
    }
}

test "pg: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), pg.pg_backend.quoteChar);
}
