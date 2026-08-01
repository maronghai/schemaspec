const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "mssql: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);

    // int
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("INT", result);
    }
    // bigint
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BIGINT", result);
    }
    // smallint
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .smallint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("SMALLINT", result);
    }
    // varchar(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NVARCHAR(128)", result);
    }
    // varchar(0) defaults to 255
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 0 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NVARCHAR(255)", result);
    }
    // decimal(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMERIC(10, 2)", result);
    }
    // boolean → BIT
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BIT", result);
    }
    // text → NVARCHAR(MAX)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .text);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NVARCHAR(MAX)", result);
    }
    // blob → VARBINARY(MAX)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARBINARY(MAX)", result);
    }
    // datetime → DATETIME2
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .datetime);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("DATETIME2", result);
    }
    // uuid → UNIQUEIDENTIFIER
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .uuid);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("UNIQUEIDENTIFIER", result);
    }
    // enum_values → NVARCHAR(255)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .enum_values = &.{ "active", "inactive" } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NVARCHAR(255)", result);
    }
}

test "mssql: quoteChar is left bracket" {
    try testing.expectEqual(@as(u8, '['), dialect.getBackend(.mssql).quoteChar);
}

test "mssql: quoteIdent wraps in brackets" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.quoteIdent(w, "users");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("[users]", result);
}

test "mssql: emitPrimaryKey omits auto_increment" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitPrimaryKey(w, true); // auto_increment=true should be ignored
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" PRIMARY KEY", result);
}

test "mssql: emitTimestampModifier uses DEFAULT CURRENT_TIMESTAMP" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitTimestampModifier(w, false);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" DEFAULT CURRENT_TIMESTAMP", result);
}

test "mssql: emitCreateView format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitCreateView(w, "active_users", "SELECT * FROM users WHERE active = 1");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("CREATE VIEW [active_users] AS\nSELECT * FROM users WHERE active = 1;\n", result);
}

test "mssql: emitEnumTypeCheck format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitEnumTypeCheck(w, "status", &.{ "active", "inactive", "pending" });
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" CHECK ([status] IN ('active', 'inactive', 'pending'))", result);
}

test "mssql: capability flags" {
    const cap = dialect.getBackend(.mssql).capability;
    try testing.expect(cap.schemas);
    try testing.expect(cap.sequences);
    try testing.expect(cap.batch_separators);
    try testing.expect(cap.generated_columns);
    try testing.expect(cap.alter_drop_column);
    try testing.expect(!cap.auto_increment);
    try testing.expect(!cap.unsigned);
    try testing.expect(!cap.enum_type);
}

test "mssql: generated column format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mssql);
    // stored
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.emitGeneratedColumn(w, "price * qty", true);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("AS (price * qty) PERSISTED", result);
    }
    // virtual
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.emitGeneratedColumn(w, "price * qty", false);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("AS (price * qty)", result);
    }
}
