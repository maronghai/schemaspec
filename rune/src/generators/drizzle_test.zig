const std = @import("std");
const gen = @import("drizzle.zig");
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

test "drizzle: single table basic columns" {
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
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "pgTable('users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "integer('id')") != null);
    // varchar now carries its length (driver default was a silent degradation).
    try testing.expect(std.mem.indexOf(u8, result, "varchar('name', { length: 64 })") != null);
}

test "drizzle: nullable column gets no .notNull()" {
    const alloc = testing.allocator;
    var col = makeTestColumn("bio", .text);
    col.flags.nullable = true;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    // Nullable should not have .notNull()
    try testing.expect(std.mem.indexOf(u8, result, "text('bio')") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".notNull()") == null);
}

test "drizzle: primary key with autoincrement" {
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
    try testing.expect(std.mem.indexOf(u8, result, ".primaryKey()") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".autoincrement()") != null);
}

test "drizzle: FK single column reference" {
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
    try testing.expect(std.mem.indexOf(u8, result, ".references(() => users.id)") != null);
}

test "drizzle: MySQL dialect uses mysqlTable" {
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
    try testing.expect(std.mem.indexOf(u8, result, "mysqlTable('users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "from 'drizzle-orm/mysql-core'") != null);
}

test "drizzle: SQLite dialect uses sqliteTable" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .sqlite);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "sqliteTable('users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "from 'drizzle-orm/sqlite-core'") != null);
}

test "drizzle: index generation" {
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
    try testing.expect(std.mem.indexOf(u8, result, "uniqueIndex('idx_users_email')") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".on(email)") != null);
}

test "drizzle: boolean and timestamp types" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("active", .boolean),
        makeTestColumn("created_at", .datetime),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "boolean('active')") != null);
    try testing.expect(std.mem.indexOf(u8, result, "timestamp('created_at')") != null);
}

test "drizzle: decimal precision and scale" {
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
    try testing.expect(std.mem.indexOf(u8, result, "decimal('price', { precision: 10, scale: 2 })") != null);
}
