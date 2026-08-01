const std = @import("std");
const gen = @import("knex.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");

const testing = std.testing;
const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumn;
const makeTestTable = ct.makeTestTable;
const makeTestTableWithFks = ct.makeTestTableWithFks;
const makeTestTableWithIndexes = ct.makeTestTableWithIndexes;
const makeTestAst = ct.makeTestAst;

test "knex: single table basic columns" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
        makeTestColumn("name", .{ .varchar = 64 }),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "exports.up = function(knex)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "exports.down = function(knex)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "createTable('users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "table.integer('id')") != null);
    try testing.expect(std.mem.indexOf(u8, result, "table.string('name', 64)") != null);
}

test "knex: primary key with autoincrement" {
    const alloc = testing.allocator;
    var col = makeTestColumn("id", .serial);
    col.flags.primary_key = true;
    col.flags.auto_increment = true;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "table.increments('id').primary()") != null);
}

test "knex: nullable column" {
    const alloc = testing.allocator;
    var col = makeTestColumn("bio", .text);
    col.flags.nullable = true;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "table.text('bio')") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".notNullable()") == null);
}

test "knex: boolean column" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("active", .boolean),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "table.boolean('active')") != null);
}

test "knex: decimal column" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("price", .{ .decimal = .{ .precision = 10, .scale = 2 } }),
    });
    defer alloc.free(cols);
    const table = makeTestTable("products", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "table.decimal('price')") != null);
}

test "knex: FK generates foreign key reference" {
    const alloc = testing.allocator;
    const user_cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(user_cols);
    const post_cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
        makeTestColumn("user_id", .int),
    });
    defer alloc.free(post_cols);
    const fk = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };
    const fks = try alloc.dupe(ast_mod.FkDecl, &.{fk});
    defer alloc.free(fks);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{
        makeTestTable("users", user_cols),
        makeTestTableWithFks("posts", post_cols, fks),
    });
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    // FK column should be excluded from table.<type>()
    try testing.expect(std.mem.indexOf(u8, result, "table.integer('user_id')") == null);
    try testing.expect(std.mem.indexOf(u8, result, "table.foreign('user_id')") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".references('users.id')") != null);
}

test "knex: index generation" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
        makeTestColumn("email", .{ .varchar = 255 }),
    });
    defer alloc.free(cols);
    const idx = ast_mod.IndexDecl{
        .kind = .unique,
        .name = "idx_users_email",
        .fields = &.{"email"},
        .descending = &.{false},
        .line_no = 1,
    };
    const indexes = try alloc.dupe(ast_mod.IndexDecl, &.{idx});
    defer alloc.free(indexes);
    const table = makeTestTableWithIndexes("users", cols, indexes);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "table.unique('email', { indexName: 'idx_users_email' })") != null);
}

test "knex: down drops tables" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "dropTableIfExists('users')") != null);
}
