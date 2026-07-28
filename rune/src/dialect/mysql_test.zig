const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "mysql: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mysql);

    // int
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("int", result);
    }
    // bigint
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bigint", result);
    }
    // varchar(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("varchar(128)", result);
    }
    // decimal(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("decimal(10, 2)", result);
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
}

test "mysql: quoteChar is backtick" {
    try testing.expectEqual(@as(u8, '`'), dialect.getBackend(.mysql).quoteChar);
}
