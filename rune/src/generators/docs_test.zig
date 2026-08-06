const std = @import("std");
const gen = @import("docs.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");

const testing = std.testing;
const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumn;
const makeTestTable = ct.makeTestTable;
const makeTestAst = ct.makeTestAst;
const makeTestAstWithCustomTypes = ct.makeTestAstWithCustomTypes;

test "docs: empty schema" {
    const alloc = testing.allocator;
    const ast = makeTestAst(&.{});
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "# Schema Documentation") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Tables:** 0") != null);
}

test "docs: single table" {
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
    try testing.expect(std.mem.indexOf(u8, result, "### `users`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "| Column |") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`id`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`name`") != null);
}

test "docs: table with comment" {
    const alloc = testing.allocator;
    var col = makeTestColumn("id", .int);
    col.comment = "Primary key";
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    var table = makeTestTable("users", cols);
    table.comment = "User accounts";
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "User accounts") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Primary key") != null);
}

test "docs: overview counts" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
        makeTestColumn("name", .{ .varchar = 64 }),
        makeTestColumn("email", .{ .varchar = 128 }),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "**Tables:** 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Total Fields:** 3") != null);
}

test "docs: multiple tables" {
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
    try testing.expect(std.mem.indexOf(u8, result, "### `users`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "### `posts`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Tables:** 2") != null);
}

test "docs: custom types section" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{
        .{
            .name = "STATUS",
            .base = .{ .enum_type = &.{ "active", "inactive", "pending" } },
            .dialect_overrides = &.{},
            .line_no = 1,
        },
    });
    defer alloc.free(custom_types);
    const ast = makeTestAstWithCustomTypes(tables, custom_types);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "## Custom Types") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`STATUS`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`active`") != null);
}

test "docs: CHECK constraints section" {
    const alloc = testing.allocator;
    var col = makeTestColumn("age", .int);
    col.check = .{
        .kind = .comparison,
        .expr = "age >= 0 AND age <= 150",
        .line_no = 1,
    };
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "**CHECK Constraints:**") != null);
    try testing.expect(std.mem.indexOf(u8, result, "age >= 0 AND age <= 150") != null);
}
