const std = @import("std");
const te = @import("template_extraction.zig");
const sp = @import("../parser/sql_parser.zig");
const sp_common = @import("../parser/sql_parser_common.zig");

const testing = std.testing;

fn makeSqlCol(name: []const u8, type_sql: []const u8) sp_common.SqlColumn {
    return .{
        .name = name,
        .type_sql = type_sql,
        .nullable = true,
        .unsigned = false,
        .auto_increment = false,
        .primary_key = false,
        .on_update_current_timestamp = false,
        .default_val = null,
        .check_expr = null,
        .comment = null,
    };
}

fn makeCols(alloc: std.mem.Allocator, cols: []const sp_common.SqlColumn) ![]sp_common.SqlColumn {
    const result = try alloc.alloc(sp_common.SqlColumn, cols.len);
    for (cols, 0..) |col, i| result[i] = col;
    return result;
}

fn makeTable(name: []const u8, cols: []sp_common.SqlColumn) sp_common.SqlTable {
    return .{
        .name = name,
        .engine = null,
        .charset = null,
        .comment = null,
        .columns = cols,
        .indexes = &.{},
        .foreign_keys = &.{},
        .checks = &.{},
    };
}

test "findTemplates: single table → no templates" {
    const alloc = testing.allocator;
    const cols = try makeCols(alloc, &.{ makeSqlCol("id", "INTEGER"), makeSqlCol("name", "TEXT") });
    const tables = try alloc.dupe(sp_common.SqlTable, &.{makeTable( "t1", cols)});
    const schema = sp.SqlSchema{ .name = null, .charset = null, .tables = tables };
    const result = try te.findTemplates(alloc, schema);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "findTemplates: two tables sharing fields → finds template" {
    const alloc = testing.allocator;
    const users_cols = try makeCols(alloc, &.{ makeSqlCol("id", "INTEGER"), makeSqlCol("name", "TEXT"), makeSqlCol("email", "TEXT") });
    const orders_cols = try makeCols(alloc, &.{ makeSqlCol("id", "INTEGER"), makeSqlCol("name", "TEXT"), makeSqlCol("total", "REAL") });
    const tables = try alloc.dupe(sp_common.SqlTable, &.{ makeTable( "users", users_cols), makeTable( "orders", orders_cols) });
    const schema = sp.SqlSchema{ .name = null, .charset = null, .tables = tables };
    const result = try te.findTemplates(alloc, schema);
    try testing.expect(result.len >= 1);
    try testing.expectEqualStrings("base", result[0].name);
    try testing.expect(result[0].fields.len >= 2);
    try testing.expect(result[0].table_indices.len >= 2);
}

test "findTemplates: no shared fields → no templates" {
    const alloc = testing.allocator;
    const t1_cols = try makeCols(alloc, &.{ makeSqlCol("a", "INTEGER"), makeSqlCol("b", "TEXT") });
    const t2_cols = try makeCols(alloc, &.{ makeSqlCol("x", "REAL"), makeSqlCol("y", "BLOB") });
    const tables = try alloc.dupe(sp_common.SqlTable, &.{ makeTable( "t1", t1_cols), makeTable( "t2", t2_cols) });
    const schema = sp.SqlSchema{ .name = null, .charset = null, .tables = tables };
    const result = try te.findTemplates(alloc, schema);
    try testing.expectEqual(@as(usize, 0), result.len);
}
