const std = @import("std");
const dialect = @import("dialect.zig");
const SqlType = @import("../types/sql_type.zig").SqlType;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "pg: renderType maps common types" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.pg);

    // int → integer
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("integer", result);
    }
    // blob → bytea
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .blob);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bytea", result);
    }
    // decimal → numeric(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("numeric(10, 2)", result);
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
    // timestamptz
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try backend.renderType(w, .timestamptz);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("timestamptz", result);
    }
}

test "pg: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), dialect.getBackend(.pg).quoteChar);
}

test "pg: lookupSym maps n to int" {
    const backend = dialect.getBackend(.pg);
    try testing.expectEqual(SqlType.int, backend.lookupSym("n"));
}

test "pg: lookupSym maps N to bigint" {
    const backend = dialect.getBackend(.pg);
    try testing.expectEqual(SqlType.bigint, backend.lookupSym("N"));
}

test "pg: lookupSym maps s to varchar(0)" {
    const backend = dialect.getBackend(.pg);
    try testing.expectEqual(SqlType{ .varchar = 0 }, backend.lookupSym("s"));
}

test "pg: lookupSym maps m to decimal(16,2)" {
    const backend = dialect.getBackend(.pg);
    try testing.expectEqual(SqlType{ .decimal = .{ .precision = 16, .scale = 2 } }, backend.lookupSym("m"));
}

test "pg: lookupSym maps b to boolean" {
    const backend = dialect.getBackend(.pg);
    try testing.expectEqual(SqlType.boolean, backend.lookupSym("b"));
}

test "pg: canOmitType returns true for _id with n" {
    try testing.expect(dialect.canOmitType("user_id", "n", false, false));
}

test "pg: canOmitType returns true for s" {
    try testing.expect(dialect.canOmitType("email", "s", false, false));
}

test "pg: emitAlterDropColumn writes DROP COLUMN" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.pg);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitAlterDropColumn(w, "email");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("DROP COLUMN \"email\"", result);
}

test "pg: emitAlterRenameColumn writes RENAME COLUMN" {
    const alloc = testing.allocator;
    const backend = dialect.getBackend(.pg);
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try backend.emitAlterRenameColumn(w, "old_name", "new_name");
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("RENAME COLUMN \"old_name\" TO \"new_name\"", result);
}
