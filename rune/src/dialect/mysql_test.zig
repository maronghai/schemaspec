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

test "mysql: lookupSym maps n to int" {
    const backend = dialect.getBackend(.mysql);
    try testing.expectEqual(SqlType.int, backend.lookupSym("n"));
}

test "mysql: lookupSym maps N to bigint" {
    const backend = dialect.getBackend(.mysql);
    try testing.expectEqual(SqlType.bigint, backend.lookupSym("N"));
}

test "mysql: lookupSym maps s to varchar(0)" {
    const backend = dialect.getBackend(.mysql);
    try testing.expectEqual(SqlType{ .varchar = 0 }, backend.lookupSym("s"));
}

test "mysql: lookupSym maps m to decimal(16,2)" {
    const backend = dialect.getBackend(.mysql);
    try testing.expectEqual(SqlType{ .decimal = .{ .precision = 16, .scale = 2 } }, backend.lookupSym("m"));
}

test "mysql: lookupSym maps b to boolean" {
    const backend = dialect.getBackend(.mysql);
    try testing.expectEqual(SqlType.boolean, backend.lookupSym("b"));
}

test "mysql: canOmitType returns true for _id with n" {
    try testing.expect(dialect.canOmitType("user_id", "n", false, false));
}

test "mysql: canOmitType returns true for s" {
    try testing.expect(dialect.canOmitType("email", "s", false, false));
}

test "mysql: canOmitType returns false for auto_increment" {
    try testing.expect(!dialect.canOmitType("id", "n", true, false));
}

test "mysql: emitAlterDropColumn writes DROP COLUMN" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mysql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitAlterDropColumn(w, "email");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("DROP COLUMN `email`", result);
}

test "mysql: emitAlterModifyColumn writes MODIFY COLUMN" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.mysql);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitAlterModifyColumn(w, "email");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    // MySQL's emitAlterModifyColumn doesn't include the column name (added by codegen)
    try testing.expectEqualStrings("MODIFY COLUMN ", result);
}
