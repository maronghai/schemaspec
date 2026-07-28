const std = @import("std");
const mysql = @import("mysql.zig");
const dialect = @import("dialect.zig");

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "mysql: renderType maps common types" {
    const alloc = testing.allocator;

    // int
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysql.mysqlRenderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("int", result);
    }
    // bigint
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysql.mysqlRenderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bigint", result);
    }
    // varchar(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysql.mysqlRenderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("varchar(128)", result);
    }
    // decimal(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysql.mysqlRenderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("decimal(10, 2)", result);
    }
    // boolean
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysql.mysqlRenderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("boolean", result);
    }
}

test "mysql: quoteChar is backtick" {
    try testing.expectEqual(@as(u8, '`'), mysql.mysql_backend.quoteChar);
}
