const std = @import("std");
const dialect = @import("dialect.zig");
const dialect_enum = @import("enum.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

const testing = std.testing;

// ─── getBackend Tests ─────────────────────────────────────────

test "getBackend: returns valid backend for all 6 dialects" {
    const dialects = [_]dialect_enum.Dialect{ .mysql, .pg, .sqlite, .mssql, .oracle, .db2 };
    inline for (dialects) |d| {
        const backend = dialect.getBackend(d);
        // All backends must have non-null function pointers
        try testing.expect(@typeInfo(@TypeOf(backend.quoteIdent)) == .pointer);
        try testing.expect(@typeInfo(@TypeOf(backend.renderType)) == .pointer);
        try testing.expect(@typeInfo(@TypeOf(backend.emitForeignKey)) == .pointer);
        try testing.expect(@typeInfo(@TypeOf(backend.emitCreateView)) == .pointer);
        try testing.expect(@typeInfo(@TypeOf(backend.emitPrimaryKey)) == .pointer);
        try testing.expect(@typeInfo(@TypeOf(backend.lookupSym)) == .pointer);
    }
}

test "getBackend: quoteChar differs by dialect" {
    try testing.expectEqual(@as(u8, '`'), dialect.getBackend(.mysql).quoteChar);
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.pg).quoteChar);
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.sqlite).quoteChar);
    try testing.expectEqual(@as(u8, '['), dialect.getBackend(.mssql).quoteChar);
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.oracle).quoteChar);
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.db2).quoteChar);
}

// ─── canOmitType Tests ────────────────────────────────────────

test "canOmitType: returns true for _id columns with int type" {
    try testing.expect(dialect.canOmitType("user_id", "n", false, false));
}

test "canOmitType: returns true for _on columns with datetime type" {
    try testing.expect(dialect.canOmitType("created_on", "d", false, false));
}

test "canOmitType: returns true for _at columns with timestamp type" {
    try testing.expect(dialect.canOmitType("deleted_at", "t", false, false));
}

test "canOmitType: returns true for s (varchar) type regardless of column name" {
    try testing.expect(dialect.canOmitType("anything", "s", false, false));
    try testing.expect(dialect.canOmitType("user_id", "s", false, false));
}

test "canOmitType: returns false for auto_increment columns" {
    try testing.expect(!dialect.canOmitType("id", "n", true, false));
}

test "canOmitType: returns false for default timestamp columns" {
    try testing.expect(!dialect.canOmitType("created_at", "t", false, true));
}

test "canOmitType: returns false for short column names" {
    try testing.expect(!dialect.canOmitType("id", "n", false, false));
}

test "canOmitType: returns false for non-varchar types on non-suffix columns" {
    try testing.expect(!dialect.canOmitType("title", "n", false, false));
}

// ─── Behavioral Flags Tests ───────────────────────────────────

test "behavioral flags: MySQL rename_needs_column_def is true" {
    const backend = dialect.getBackend(.mysql);
    try testing.expect(backend.rename_needs_column_def);
    try testing.expect(backend.modify_needs_column_def);
}

test "behavioral flags: PG modify_column_def_skips_name is true" {
    const backend = dialect.getBackend(.pg);
    try testing.expect(backend.modify_column_def_skips_name);
}

// ─── lookupSym Tests ──────────────────────────────────────────

test "lookupSym: all backends map basic symbols" {
    const dialects = [_]dialect_enum.Dialect{ .mysql, .pg, .sqlite, .mssql, .oracle, .db2 };
    inline for (dialects) |d| {
        const backend = dialect.getBackend(d);
        // "n" should map to int for all dialects
        const result = backend.lookupSym("n");
        try testing.expect(result != null);
        try testing.expectEqual(SqlType.int, result.?);
    }
}

// ─── renderType Tests ─────────────────────────────────────────

test "renderType: dispatches to render_fn for parameterized types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mysql);

    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.renderType(w, .{ .varchar = 255 });
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("varchar(255)", result);
}

test "renderType: dispatches to comptime_str for simple types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.pg);

    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.renderType(w, .text);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("text", result);
}
