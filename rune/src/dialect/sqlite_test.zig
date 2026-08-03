const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "sqlite: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.sqlite);

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
    // text → TEXT
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .text);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("TEXT", result);
    }
    // decimal → NUMERIC(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("NUMERIC(10, 2)", result);
    }
    // boolean → INTEGER
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("INTEGER", result);
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
}

test "sqlite: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.sqlite).quoteChar);
}

test "sqlite: lookupSym maps n to int" {
    const backend = dialect.getBackend(.sqlite);
    try testing.expectEqual(SqlType.int, backend.lookupSym("n"));
}

test "sqlite: lookupSym maps N to int" {
    const backend = dialect.getBackend(.sqlite);
    try testing.expectEqual(SqlType.int, backend.lookupSym("N"));
}

test "sqlite: lookupSym maps s to varchar(0)" {
    const backend = dialect.getBackend(.sqlite);
    try testing.expectEqual(SqlType{ .varchar = 0 }, backend.lookupSym("s"));
}

test "sqlite: lookupSym maps m to decimal(16,2)" {
    const backend = dialect.getBackend(.sqlite);
    try testing.expectEqual(SqlType{ .decimal = .{ .precision = 16, .scale = 2 } }, backend.lookupSym("m"));
}

test "sqlite: lookupSym maps b to boolean" {
    const backend = dialect.getBackend(.sqlite);
    try testing.expectEqual(SqlType.boolean, backend.lookupSym("b"));
}

test "sqlite: canOmitType returns true for _id with n" {
    try testing.expect(dialect.canOmitType("user_id", "n", false, false));
}

test "sqlite: canOmitType returns true for s" {
    try testing.expect(dialect.canOmitType("email", "s", false, false));
}

test "sqlite: emitAlterDropColumn writes warning" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.sqlite);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitAlterDropColumn(w, "email");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expect(std.mem.startsWith(u8, result, "-- WARNING: DROP COLUMN"));
}
