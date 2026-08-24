const std = @import("std");
const gen = @import("sqlalchemy.zig");
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

test "sqlalchemy: single table basic columns" {
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
    try testing.expect(std.mem.indexOf(u8, result, "class users(Base):") != null);
    try testing.expect(std.mem.indexOf(u8, result, "__tablename__ = 'users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Column(Integer") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Column(String(64)") != null);
}

test "sqlalchemy: primary key with autoincrement" {
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
    try testing.expect(std.mem.indexOf(u8, result, "primary_key=True") != null);
    try testing.expect(std.mem.indexOf(u8, result, "autoincrement=True") != null);
}

test "sqlalchemy: nullable column" {
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
    // Nullable should not have nullable=False
    try testing.expect(std.mem.indexOf(u8, result, "Column(Text)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "nullable=False") == null);
}

test "sqlalchemy: boolean column" {
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
    try testing.expect(std.mem.indexOf(u8, result, "Column(Boolean") != null);
}

test "sqlalchemy: decimal column" {
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
    try testing.expect(std.mem.indexOf(u8, result, "Numeric(precision=10, scale=2)") != null);
}

test "sqlalchemy: FK generates ForeignKey" {
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
    // FK columns are real columns — they must appear with their ForeignKey
    // constraint (v0.334.0: the column itself was previously dropped).
    try testing.expect(std.mem.indexOf(u8, result, "user_id = Column(Integer, ForeignKey('users.id')") != null);
}

test "sqlalchemy: composite index generates __table_args__" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
        makeTestColumn("a", .int),
        makeTestColumn("b", .int),
    });
    defer alloc.free(cols);
    const idx = ast_mod.IndexDecl{
        .kind = .regular,
        .name = "idx_ab",
        .fields = &.{ "a", "b" },
        .descending = &.{ false, false },
        .line_no = 1,
    };
    const indexes = try alloc.dupe(ast_mod.IndexDecl, &.{idx});
    defer alloc.free(indexes);
    const table = makeTestTableWithIndexes("t", cols, indexes);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .pg);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "__table_args__") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Index('idx_ab'") != null);
}

test "sqlalchemy: multiple tables" {
    const alloc = testing.allocator;
    const cols1 = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols1);
    const cols2 = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols2);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{
        makeTestTable("users", cols1),
        makeTestTable("posts", cols2),
    });
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "class users(Base):") != null);
    try testing.expect(std.mem.indexOf(u8, result, "class posts(Base):") != null);
    try testing.expect(std.mem.indexOf(u8, result, "__tablename__ = 'users'") != null);
    try testing.expect(std.mem.indexOf(u8, result, "__tablename__ = 'posts'") != null);
}
