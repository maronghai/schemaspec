const std = @import("std");
const tr = @import("type_registry.zig");
const sql_type_mod = @import("sql_type.zig");

const testing = std.testing;

test "registry: lookupSqlTypeDirect for all core types" {
    const int_mysql = tr.lookupSqlTypeDirect("n", .mysql);
    try testing.expect(int_mysql != null);
    try testing.expectEqual(sql_type_mod.SqlType.int, int_mysql.?);

    const int_pg = tr.lookupSqlTypeDirect("n", .pg);
    try testing.expect(int_pg != null);
    try testing.expectEqual(sql_type_mod.SqlType.int, int_pg.?);

    const bigint = tr.lookupSqlTypeDirect("N", .mysql);
    try testing.expect(bigint != null);
    try testing.expectEqual(sql_type_mod.SqlType.bigint, bigint.?);

    const text = tr.lookupSqlTypeDirect("S", .mysql);
    try testing.expect(text != null);
    try testing.expectEqual(sql_type_mod.SqlType.text, text.?);

    const boolean = tr.lookupSqlTypeDirect("b", .pg);
    try testing.expect(boolean != null);
    try testing.expectEqual(sql_type_mod.SqlType.boolean, boolean.?);

    const blob = tr.lookupSqlTypeDirect("B", .mysql);
    try testing.expect(blob != null);
    try testing.expectEqual(sql_type_mod.SqlType.blob, blob.?);

    const json = tr.lookupSqlTypeDirect("j", .mysql);
    try testing.expect(json != null);
    try testing.expectEqual(sql_type_mod.SqlType.json, json.?);

    const datetime = tr.lookupSqlTypeDirect("t", .mysql);
    try testing.expect(datetime != null);
    try testing.expectEqual(sql_type_mod.SqlType.datetime, datetime.?);

    try testing.expect(tr.lookupSqlTypeDirect("x", .mysql) == null);
}

test "registry: lookupSqlType renders correct strings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const int_mysql = tr.lookupSqlType("n", .mysql, alloc);
    try testing.expect(int_mysql != null);
    try testing.expectEqualStrings("int", int_mysql.?);

    const int_pg = tr.lookupSqlType("n", .pg, alloc);
    try testing.expect(int_pg != null);
    try testing.expectEqualStrings("integer", int_pg.?);

    const int_sqlite = tr.lookupSqlType("n", .sqlite, alloc);
    try testing.expect(int_sqlite != null);
    try testing.expectEqualStrings("INTEGER", int_sqlite.?);

    const bigint_mysql = tr.lookupSqlType("N", .mysql, alloc);
    try testing.expect(bigint_mysql != null);
    try testing.expectEqualStrings("bigint", bigint_mysql.?);

    const text_mysql = tr.lookupSqlType("S", .mysql, alloc);
    try testing.expect(text_mysql != null);
    try testing.expectEqualStrings("text", text_mysql.?);

    const boolean_pg = tr.lookupSqlType("b", .pg, alloc);
    try testing.expect(boolean_pg != null);
    try testing.expectEqualStrings("boolean", boolean_pg.?);

    const blob_mysql = tr.lookupSqlType("B", .mysql, alloc);
    try testing.expect(blob_mysql != null);
    try testing.expectEqualStrings("blob", blob_mysql.?);

    const bytea_pg = tr.lookupSqlType("B", .pg, alloc);
    try testing.expect(bytea_pg != null);
    try testing.expectEqualStrings("bytea", bytea_pg.?);

    const json_mysql = tr.lookupSqlType("j", .mysql, alloc);
    try testing.expect(json_mysql != null);
    try testing.expectEqualStrings("json", json_mysql.?);

    const datetime_mysql = tr.lookupSqlType("t", .mysql, alloc);
    try testing.expect(datetime_mysql != null);
    try testing.expectEqualStrings("datetime", datetime_mysql.?);

    const timestamp_pg = tr.lookupSqlType("t", .pg, alloc);
    try testing.expect(timestamp_pg != null);
    try testing.expectEqualStrings("timestamp", timestamp_pg.?);

    try testing.expect(tr.lookupSqlType("x", .mysql, alloc) == null);
}

test "registry: isCoreType" {
    try testing.expect(tr.isCoreType("n"));
    try testing.expect(tr.isCoreType("S"));
    try testing.expect(!tr.isCoreType("x"));
    try testing.expect(!tr.isCoreType("uuid"));
}
