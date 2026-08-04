const std = @import("std");
const st = @import("sql_type.zig");
const SqlType = st.SqlType;
const reverse_map = @import("../reverse/map.zig");

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

// ─── Forward/Reverse Consistency Test ──────────────────────────
// Verifies that REVERSE_MAP canonical entries (sql_type != null)
// agree with SqlType.toSql() for the base type in all dialects.
// When adding a new type, update BOTH SqlType.toSql() and REVERSE_MAP.

fn forwardNameAlloc(dialect: @import("../dialect/enum.zig").Dialect, sql_type: SqlType) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    try sql_type.toSql(dialect, &aw.writer);
    return try aw.toOwnedSlice();
}

fn expectForwardMatchesReverse(dialect: @import("../dialect/enum.zig").Dialect, forward_sql: []const u8, rev_entry: reverse_map.ReverseMapping) !void {
    const rev_sql = switch (dialect) {
        .mysql => rev_entry.types.mysql,
        .pg => rev_entry.types.pg,
        .sqlite => rev_entry.types.sqlite,
        .mssql => rev_entry.types.mssql,
        .oracle => rev_entry.types.oracle,
        .db2 => rev_entry.types.db2,
    };
    try testing.expectEqualStrings(rev_sql, forward_sql);
}

test "consistency: REVERSE_MAP canonical entries match SqlType.toSql" {
    for (reverse_map.REVERSE_MAP) |entry| {
        if (entry.sql_type) |sql_type| {
            switch (sql_type) {
                .varchar, .decimal, .enum_values, .raw_sql, .passthrough => continue,
                else => {},
            }
            const mysql = try forwardNameAlloc(.mysql, sql_type);
            defer testing.allocator.free(mysql);
            try expectForwardMatchesReverse(.mysql, mysql, entry);

            const pg = try forwardNameAlloc(.pg, sql_type);
            defer testing.allocator.free(pg);
            try expectForwardMatchesReverse(.pg, pg, entry);

            const sqlite = try forwardNameAlloc(.sqlite, sql_type);
            defer testing.allocator.free(sqlite);
            try expectForwardMatchesReverse(.sqlite, sqlite, entry);
        }
    }
}
