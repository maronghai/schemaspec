const std = @import("std");
const st = @import("sql_type.zig");
const SqlType = st.SqlType;

const testing = std.testing;

// ─── SqlType toSql Tests ─────────────────────────────────────

test "SqlType: int renders correctly" {
    const t: SqlType = .int;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("int", result);
}

test "SqlType: bigint renders correctly" {
    const t: SqlType = .bigint;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("bigint", result);
}

test "SqlType: text renders correctly" {
    const t: SqlType = .text;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("text", result);
}

test "SqlType: varchar renders correctly" {
    const t: SqlType = .{ .varchar = 255 };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("varchar(255)", result);
}

test "SqlType: boolean renders correctly" {
    const t: SqlType = .boolean;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("boolean", result);
}

test "SqlType: datetime renders correctly" {
    const t: SqlType = .datetime;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("datetime", result);
}

test "SqlType: json renders correctly" {
    const t: SqlType = .json;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("json", result);
}

test "SqlType: uuid renders correctly for PG" {
    const t: SqlType = .uuid;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.pg, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("uuid", result);
}

test "SqlType: boolean renders correctly for PG" {
    const t: SqlType = .boolean;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.pg, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("boolean", result);
}

test "SqlType: int renders correctly for SQLite" {
    const t: SqlType = .int;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.sqlite, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("INTEGER", result);
}

test "SqlType: boolean renders correctly for SQLite" {
    const t: SqlType = .boolean;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.sqlite, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("INTEGER", result);
}

test "SqlType: varchar(0) renders as varchar(255) for MySQL" {
    const t: SqlType = .{ .varchar = 0 };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("varchar(255)", result);
}

// ─── SqlType toJsonSchema Tests ──────────────────────────────

test "SqlType toJsonSchema: int → integer" {
    const t: SqlType = .int;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"integer\"}", result);
}

test "SqlType toJsonSchema: varchar(100) → string with maxLength" {
    const t: SqlType = .{ .varchar = 100 };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\",\"maxLength\":100}", result);
}

test "SqlType toJsonSchema: text → string" {
    const t: SqlType = .text;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\"}", result);
}

test "SqlType toJsonSchema: boolean → boolean" {
    const t: SqlType = .boolean;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"boolean\"}", result);
}

test "SqlType toJsonSchema: json → object" {
    const t: SqlType = .json;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"object\"}", result);
}

test "SqlType toJsonSchema: datetime → date-time string" {
    const t: SqlType = .datetime;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\",\"format\":\"date-time\"}", result);
}

test "SqlType toJsonSchema: uuid → uuid string" {
    const t: SqlType = .uuid;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\",\"format\":\"uuid\"}", result);
}

test "SqlType toJsonSchema: decimal(10,2) → number with multipleOf" {
    const t: SqlType = .{ .decimal = .{ .precision = 10, .scale = 2 } };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"number\",\"multipleOf\":0.01}", result);
}

test "SqlType toJsonSchema: decimal(10,0) → integer" {
    const t: SqlType = .{ .decimal = .{ .precision = 10, .scale = 0 } };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"integer\"}", result);
}

test "SqlType toJsonSchema: blob → base64 string" {
    const t: SqlType = .blob;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try t.toJsonSchema(&aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\",\"contentEncoding\":\"base64\"}", result);
}
