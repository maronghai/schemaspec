const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "oracle: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);

    // int → NUMBER(10)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMBER(10)", result);
    }
    // bigint → NUMBER(19)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMBER(19)", result);
    }
    // smallint → NUMBER(5)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .smallint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMBER(5)", result);
    }
    // varchar(128) → VARCHAR2(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR2(128)", result);
    }
    // varchar(0) defaults to VARCHAR2(255)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .varchar = 0 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR2(255)", result);
    }
    // decimal(10, 2) → NUMBER(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMBER(10, 2)", result);
    }
    // boolean → NUMBER(1)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMBER(1)", result);
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
    // uuid → RAW(16)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .uuid);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("RAW(16)", result);
    }
    // enum_values → VARCHAR2(255)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .enum_values = &.{ "active", "inactive" } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("VARCHAR2(255)", result);
    }
}

test "oracle: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.oracle).quoteChar);
}

test "oracle: quoteIdent wraps in double-quotes" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.quoteIdent(w, "users");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("\"users\"", result);
}

test "oracle: emitPrimaryKey omits auto_increment" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitPrimaryKey(w, true);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" PRIMARY KEY", result);
}

test "oracle: emitTimestampModifier uses DEFAULT CURRENT_TIMESTAMP" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitTimestampModifier(w, false);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" DEFAULT CURRENT_TIMESTAMP", result);
}

test "oracle: emitCreateView format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitCreateView(w, "active_users", "SELECT * FROM users WHERE active = 1");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("CREATE OR REPLACE VIEW \"active_users\" AS\nSELECT * FROM users WHERE active = 1;\n", result);
}

test "oracle: emitEnumTypeCheck format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitEnumTypeCheck(w, "status", &.{ "active", "inactive", "pending" });
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings(" CHECK (\"status\" IN ('active', 'inactive', 'pending'))", result);
}

test "oracle: capability flags" {
    const cap = dialect.getBackend(.oracle).capability;
    try testing.expect(cap.standalone_comments);
    try testing.expect(cap.schemas);
    try testing.expect(cap.sequences);
    try testing.expect(cap.generated_columns);
    try testing.expect(cap.alter_drop_column);
    try testing.expect(!cap.auto_increment);
    try testing.expect(!cap.unsigned);
    try testing.expect(!cap.enum_type);
}

test "oracle: generated column format" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.oracle);
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
