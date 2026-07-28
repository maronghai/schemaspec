const std = @import("std");
const sqlite = @import("sqlite.zig");
const dialect = @import("dialect.zig");

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "sqlite: renderType maps common types" {
    const alloc = testing.allocator;

    // int → INTEGER
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try sqlite.sqliteRenderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("INTEGER", result);
    }
    // text → TEXT
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try sqlite.sqliteRenderType(w, .text);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("TEXT", result);
    }
    // decimal → NUMERIC(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try sqlite.sqliteRenderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMERIC(10, 2)", result);
    }
    // boolean → INTEGER
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try sqlite.sqliteRenderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("INTEGER", result);
    }
    // blob → BLOB
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try sqlite.sqliteRenderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BLOB", result);
    }
}

test "sqlite: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), sqlite.sqlite_backend.quoteChar);
}
