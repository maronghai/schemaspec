const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const Dialect = dialect_enum.Dialect;

// ─── Type Registry: Single source of truth for SS types ─────
//
// Production code uses lookupSqlTypeDirect() which returns SqlType variants.
// lookupSqlType() is a convenience wrapper that takes an allocator.
//
// The actual per-dialect mapping lives in each DialectBackend.lookupSym.
// This module is now a thin delegation layer — adding a new SS type only
// requires adding one entry to the relevant backend's lookupSym function.

/// Look up SqlType variant directly for a SS symbol in a given dialect.
/// Delegates to DialectBackend.lookupSym (the vtable).
pub fn lookupSqlTypeDirect(sym: []const u8, dialect: Dialect) ?sql_type_mod.SqlType {
    const backend = dialect_mod.getBackend(dialect);
    return backend.lookupSym(sym);
}

/// Look up SQL type name for a SS symbol in a given dialect.
/// Convenience wrapper — delegates to lookupSqlTypeDirect + SqlType.toSql.
pub fn lookupSqlType(sym: []const u8, dialect: Dialect, alloc: std.mem.Allocator) ?[]const u8 {
    const sql_type = lookupSqlTypeDirect(sym, dialect) orelse return null;
    var aw = std.Io.Writer.Allocating.init(alloc);
    sql_type.toSql(dialect, &aw.writer) catch return null;
    return aw.toOwnedSlice(alloc) catch null;
}

/// Check if a SS symbol is a known core type.
pub fn isCoreType(sym: []const u8) bool {
    return lookupSqlTypeDirect(sym, .mysql) != null;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "registry: lookupSqlTypeDirect for all core types" {
    const int_mysql = lookupSqlTypeDirect("n", .mysql);
    try testing.expect(int_mysql != null);
    try testing.expectEqual(sql_type_mod.SqlType.int, int_mysql.?);

    const int_pg = lookupSqlTypeDirect("n", .pg);
    try testing.expect(int_pg != null);
    try testing.expectEqual(sql_type_mod.SqlType.int, int_pg.?);

    const bigint = lookupSqlTypeDirect("N", .mysql);
    try testing.expect(bigint != null);
    try testing.expectEqual(sql_type_mod.SqlType.bigint, bigint.?);

    const text = lookupSqlTypeDirect("S", .mysql);
    try testing.expect(text != null);
    try testing.expectEqual(sql_type_mod.SqlType.text, text.?);

    const boolean = lookupSqlTypeDirect("b", .pg);
    try testing.expect(boolean != null);
    try testing.expectEqual(sql_type_mod.SqlType.boolean, boolean.?);

    const blob = lookupSqlTypeDirect("B", .mysql);
    try testing.expect(blob != null);
    try testing.expectEqual(sql_type_mod.SqlType.blob, blob.?);

    const json = lookupSqlTypeDirect("j", .mysql);
    try testing.expect(json != null);
    try testing.expectEqual(sql_type_mod.SqlType.json, json.?);

    const datetime = lookupSqlTypeDirect("t", .mysql);
    try testing.expect(datetime != null);
    try testing.expectEqual(sql_type_mod.SqlType.datetime, datetime.?);

    try testing.expect(lookupSqlTypeDirect("x", .mysql) == null);
}

test "registry: lookupSqlType renders correct strings" {
    const alloc = testing.allocator;
    const int_mysql = lookupSqlType("n", .mysql, alloc);
    try testing.expect(int_mysql != null);
    try testing.expectEqualStrings("int", int_mysql.?);

    const int_pg = lookupSqlType("n", .pg, alloc);
    try testing.expect(int_pg != null);
    try testing.expectEqualStrings("integer", int_pg.?);

    const int_sqlite = lookupSqlType("n", .sqlite, alloc);
    try testing.expect(int_sqlite != null);
    try testing.expectEqualStrings("INTEGER", int_sqlite.?);

    const bigint_mysql = lookupSqlType("N", .mysql, alloc);
    try testing.expect(bigint_mysql != null);
    try testing.expectEqualStrings("bigint", bigint_mysql.?);

    const text_mysql = lookupSqlType("S", .mysql, alloc);
    try testing.expect(text_mysql != null);
    try testing.expectEqualStrings("text", text_mysql.?);

    const boolean_pg = lookupSqlType("b", .pg, alloc);
    try testing.expect(boolean_pg != null);
    try testing.expectEqualStrings("boolean", boolean_pg.?);

    const blob_mysql = lookupSqlType("B", .mysql, alloc);
    try testing.expect(blob_mysql != null);
    try testing.expectEqualStrings("blob", blob_mysql.?);

    const bytea_pg = lookupSqlType("B", .pg, alloc);
    try testing.expect(bytea_pg != null);
    try testing.expectEqualStrings("bytea", bytea_pg.?);

    const json_mysql = lookupSqlType("j", .mysql, alloc);
    try testing.expect(json_mysql != null);
    try testing.expectEqualStrings("json", json_mysql.?);

    const datetime_mysql = lookupSqlType("t", .mysql, alloc);
    try testing.expect(datetime_mysql != null);
    try testing.expectEqualStrings("datetime", datetime_mysql.?);

    const timestamp_pg = lookupSqlType("t", .pg, alloc);
    try testing.expect(timestamp_pg != null);
    try testing.expectEqualStrings("timestamp", timestamp_pg.?);

    try testing.expect(lookupSqlType("x", .mysql, alloc) == null);
}

test "registry: isCoreType" {
    try testing.expect(isCoreType("n"));
    try testing.expect(isCoreType("S"));
    try testing.expect(!isCoreType("x"));
    try testing.expect(!isCoreType("uuid"));
}
