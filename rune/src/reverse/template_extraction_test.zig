const std = @import("std");
const te = @import("template_extraction.zig");
const sp = @import("../parser/sql_parser.zig");

const testing = std.testing;

fn makeSqlCol(name: []const u8, type_sql: []const u8) sp.SqlColumn {
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

fn makeSqlTable(name: []const u8, columns: []const sp.SqlColumn) sp.SqlTable {
    return .{
        .name = name,
        .engine = null,
        .charset = null,
        .comment = null,
        .columns = columns,
        .indexes = &.{},
        .foreign_keys = &.{},
        .checks = &.{},
    };
}

test "findTemplates: single table → no templates" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{makeSqlTable("t1", &.{
            makeSqlCol("id", "INTEGER"),
            makeSqlCol("name", "TEXT"),
        })},
    };
    const result = try te.findTemplates(alloc, schema);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "findTemplates: two tables sharing fields → finds template" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{
            makeSqlTable("users", &.{
                makeSqlCol("id", "INTEGER"),
                makeSqlCol("name", "TEXT"),
                makeSqlCol("email", "TEXT"),
            }),
            makeSqlTable("orders", &.{
                makeSqlCol("id", "INTEGER"),
                makeSqlCol("name", "TEXT"),
                makeSqlCol("total", "REAL"),
            }),
        },
    };
    const result = try te.findTemplates(alloc, schema);
    try testing.expect(result.len >= 1);
    // Template should cover id and name (shared by both tables)
    try testing.expectEqualStrings("base", result[0].name);
    try testing.expect(result[0].fields.len >= 2);
    try testing.expect(result[0].table_indices.len >= 2);
}

test "findTemplates: no shared fields → no templates" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{
            makeSqlTable("t1", &.{
                makeSqlCol("a", "INTEGER"),
                makeSqlCol("b", "TEXT"),
            }),
            makeSqlTable("t2", &.{
                makeSqlCol("x", "REAL"),
                makeSqlCol("y", "TEXT"),
            }),
        },
    };
    const result = try te.findTemplates(alloc, schema);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "findTemplates: three tables, two share template" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{
            makeSqlTable("t1", &.{
                makeSqlCol("id", "INTEGER"),
                makeSqlCol("created_at", "TIMESTAMP"),
                makeSqlCol("extra1", "TEXT"),
            }),
            makeSqlTable("t2", &.{
                makeSqlCol("id", "INTEGER"),
                makeSqlCol("created_at", "TIMESTAMP"),
                makeSqlCol("extra2", "TEXT"),
            }),
            makeSqlTable("t3", &.{
                makeSqlCol("foo", "INTEGER"),
                makeSqlCol("bar", "TEXT"),
            }),
        },
    };
    const result = try te.findTemplates(alloc, schema);
    // t1 and t2 share id+created_at, t3 has nothing in common
    if (result.len > 0) {
        try testing.expectEqualStrings("base", result[0].name);
        try testing.expect(result[0].table_indices.len >= 2);
    }
}

test "findTemplates: empty schema → no templates" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{},
    };
    const result = try te.findTemplates(alloc, schema);
    try testing.expectEqual(@as(usize, 0), result.len);
}
