const std = @import("std");
const rc = @import("codegen.zig");
const sp = @import("../parser/sql_parser.zig");
const sp_common = @import("../parser/sql_parser_common.zig");
const ReverseCodegen = rc.ReverseCodegen;

const testing = std.testing;

fn makeTestColumn(name: []const u8, type_sql: []const u8) sp_common.SqlColumn {
    return sp_common.SqlColumn{
        .name = name,
        .type_sql = type_sql,
        .nullable = false,
        .unsigned = false,
        .auto_increment = false,
        .primary_key = false,
        .on_update_current_timestamp = false,
        .default_val = null,
        .check_expr = null,
        .comment = null,
        .sym_override = null,
    };
}

fn makeTestTable(name: []const u8, columns: []sp_common.SqlColumn) sp_common.SqlTable {
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

test "ReverseCodegen basic generate" {
    const alloc = testing.allocator;
    const columns = try alloc.alloc(sp_common.SqlColumn, 2);
    columns[0] = .{ .name = "id", .type_sql = "INTEGER", .nullable = false, .unsigned = false, .auto_increment = true, .primary_key = true, .on_update_current_timestamp = false, .default_val = null, .check_expr = null, .comment = null, .sym_override = "n" };
    columns[1] = .{ .name = "name", .type_sql = "TEXT", .nullable = false, .unsigned = false, .auto_increment = false, .primary_key = false, .on_update_current_timestamp = false, .default_val = null, .check_expr = null, .comment = null, .sym_override = "s32" };
    const schema = sp.SqlSchema{
        .name = "testdb",
        .charset = "utf8mb4",
        .tables = try alloc.dupe(sp_common.SqlTable, &.{makeTestTable("users", columns)}),
    };
    var rgen = ReverseCodegen.init(alloc, .sqlite);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(schema.tables);
    defer alloc.free(columns);

    try testing.expect(std.mem.indexOf(u8, output, "$ testdb") != null);
    try testing.expect(std.mem.indexOf(u8, output, "# users") != null);
    try testing.expect(std.mem.indexOf(u8, output, "id n ++") != null);
    try testing.expect(std.mem.indexOf(u8, output, "name s32") != null);
}

test "ReverseCodegen schema header omits default charset" {
    const alloc = testing.allocator;
    const columns = try alloc.alloc(sp_common.SqlColumn, 1);
    columns[0] = makeTestColumn("id", "INTEGER");
    const schema = sp.SqlSchema{
        .name = "mydb",
        .charset = "utf8mb4",
        .tables = try alloc.dupe(sp_common.SqlTable, &.{makeTestTable("t1", columns)}),
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(schema.tables);
    defer alloc.free(columns);

    // Default charset should be omitted
    try testing.expect(std.mem.indexOf(u8, output, "$ mydb") != null);
    try testing.expect(std.mem.indexOf(u8, output, "utf8mb4") == null);
}

test "ReverseCodegen schema header includes non-default charset" {
    const alloc = testing.allocator;
    const columns = try alloc.alloc(sp_common.SqlColumn, 1);
    columns[0] = makeTestColumn("id", "INTEGER");
    const schema = sp.SqlSchema{
        .name = "mydb",
        .charset = "latin1",
        .tables = try alloc.dupe(sp_common.SqlTable, &.{makeTestTable("t1", columns)}),
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(schema.tables);
    defer alloc.free(columns);

    try testing.expect(std.mem.indexOf(u8, output, "$ mydb latin1") != null);
}

test "ReverseCodegen table with comment" {
    const alloc = testing.allocator;
    const columns = try alloc.alloc(sp_common.SqlColumn, 1);
    columns[0] = makeTestColumn("id", "INTEGER");
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = try alloc.dupe(sp_common.SqlTable, &.{.{
            .name = "users",
            .engine = null,
            .charset = null,
            .comment = "User accounts",
            .columns = columns,
            .indexes = &.{},
            .foreign_keys = &.{},
            .checks = &.{},
        }}),
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(schema.tables);
    defer alloc.free(columns);

    try testing.expect(std.mem.indexOf(u8, output, "# users : User accounts") != null);
}

test "ReverseCodegen multiple tables" {
    const alloc = testing.allocator;
    const cols1 = try alloc.alloc(sp_common.SqlColumn, 1);
    cols1[0] = makeTestColumn("id", "INTEGER");
    const cols2 = try alloc.alloc(sp_common.SqlColumn, 1);
    cols2[0] = makeTestColumn("user_id", "INTEGER");
    const tables = try alloc.alloc(sp_common.SqlTable, 2);
    tables[0] = makeTestTable("users", cols1);
    tables[1] = makeTestTable("posts", cols2);
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = tables,
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(tables);
    defer alloc.free(cols1);
    defer alloc.free(cols2);

    try testing.expect(std.mem.indexOf(u8, output, "# users") != null);
    try testing.expect(std.mem.indexOf(u8, output, "# posts") != null);
}

test "ReverseCodegen FK shorthand form" {
    const alloc = testing.allocator;
    const columns = try alloc.alloc(sp_common.SqlColumn, 1);
    columns[0] = makeTestColumn("user_id", "INTEGER");
    const fks = try alloc.alloc(sp_common.SqlForeignKey, 1);
    fks[0] = .{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
    };
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = try alloc.dupe(sp_common.SqlTable, &.{.{
            .name = "posts",
            .engine = null,
            .charset = null,
            .comment = null,
            .columns = columns,
            .indexes = &.{},
            .foreign_keys = fks,
            .checks = &.{},
        }}),
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);
    defer alloc.free(schema.tables);
    defer alloc.free(columns);
    defer alloc.free(fks);

    // Shorthand FK: > user_id users.id
    try testing.expect(std.mem.indexOf(u8, output, "> user_id users.id") != null);
}

test "ReverseCodegen empty schema" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{},
    };
    var rgen = ReverseCodegen.init(alloc, .mysql);
    const output = try rgen.generate(schema);
    defer alloc.free(output);

    // Empty schema produces minimal output
    try testing.expect(output.len == 0 or std.mem.indexOf(u8, output, "$") == null);
}
