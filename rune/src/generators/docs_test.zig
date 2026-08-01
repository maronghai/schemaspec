const std = @import("std");
const gen = @import("docs.zig");
const typed_ast = @import("../types/typed_ast.zig");
const dialect_enum = @import("../dialect/enum.zig");

const testing = std.testing;
const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumn;
const makeTestTable = ct.makeTestTable;
const makeTestAst = ct.makeTestAst;

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
