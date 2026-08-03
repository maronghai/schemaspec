const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "db2: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);

    // int → INTEGER
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("INTEGER", result);
    }
    // bigint → BIGINT
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BIGINT", result);
    }
    // smallint → SMALLINT
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .smallint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("SMALLINT", result);
    }
    // varchar(128) → VARCHAR(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR(128)", result);
    }
    // varchar(0) defaults to VARCHAR(255)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 0 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR(255)", result);
    }
    // decimal(10, 2) → DECIMAL(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("DECIMAL(10, 2)", result);
    }
    // boolean → BOOLEAN
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BOOLEAN", result);
    }
    // text → CLOB
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .text);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("CLOB", result);
    }
    // blob → BLOB
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("BLOB", result);
    }
    // datetime → TIMESTAMP
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .datetime);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("TIMESTAMP", result);
    }
    // uuid → CHAR(16) FOR BIT DATA
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .uuid);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("CHAR(16) FOR BIT DATA", result);
    }
    // enum_values → VARCHAR(255)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .enum_values = &.{ "active", "inactive" } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR(255)", result);
    }
}

test "db2: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.db2).quoteChar);
}

test "db2: quoteIdent wraps in double-quotes" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.quoteIdent(w, "users");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("\"users\"", result);
}

test "db2: emitPrimaryKey with auto_increment uses GENERATED ALWAYS AS IDENTITY" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitPrimaryKey(w, true);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" PRIMARY KEY GENERATED ALWAYS AS IDENTITY", result);
}

test "db2: emitPrimaryKey without auto_increment" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitPrimaryKey(w, false);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" PRIMARY KEY", result);
}

test "db2: emitTimestampModifier uses DEFAULT CURRENT_TIMESTAMP" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitTimestampModifier(w, false);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" DEFAULT CURRENT_TIMESTAMP", result);
}

test "db2: emitCreateView format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitCreateView(w, "active_users", "SELECT * FROM users WHERE active = 1");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("CREATE OR REPLACE VIEW \"active_users\" AS\nSELECT * FROM users WHERE active = 1;\n", result);
}

test "db2: emitEnumTypeCheck format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitEnumTypeCheck(w, "status", &.{ "active", "inactive", "pending" });
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" CHECK (\"status\" IN ('active', 'inactive', 'pending'))", result);
}

test "db2: generated column format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.db2);
    // stored
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.emitGeneratedColumn(w, "price * qty", true);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("GENERATED ALWAYS AS (price * qty) STORED", result);
    }
    // virtual
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.emitGeneratedColumn(w, "price * qty", false);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("GENERATED ALWAYS AS (price * qty) VIRTUAL", result);
    }
}
