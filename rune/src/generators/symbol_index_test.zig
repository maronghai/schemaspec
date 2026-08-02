const std = @import("std");
const gen = @import("symbol_index.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ct = @import("common_test.zig");

const testing = std.testing;
const makeTestColumn = ct.makeTestColumn;
const makeTestTable = ct.makeTestTable;
const makeTestAst = ct.makeTestAst;

test "symbol-index: empty schema" {
    const alloc = testing.allocator;
    const ast = makeTestAst(&.{});
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"tableCount\": 0") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"tables\": [") != null);
}

test "symbol-index: single table" {
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
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"id\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"int\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"varchar(64)\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"tableCount\": 1") != null);
}

test "symbol-index: column with comment" {
    const alloc = testing.allocator;
    var col = makeTestColumn("id", .int);
    col.comment = "Primary key";
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"comment\": \"Primary key\"") != null);
}

test "symbol-index: column with flags" {
    const alloc = testing.allocator;
    const col = ct.makeTestColumnWithFlags("id", .int, .{ .primary_key = true, .nullable = true });
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"primaryKey\": true") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"nullable\": true") != null);
}

test "symbol-index: multiple tables" {
    const alloc = testing.allocator;
    const cols1 = try alloc.dupe(typed_ast.TypedColumn, &.{makeTestColumn("id", .int)});
    defer alloc.free(cols1);
    const cols2 = try alloc.dupe(typed_ast.TypedColumn, &.{makeTestColumn("id", .int)});
    defer alloc.free(cols2);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{
        makeTestTable("users", cols1),
        makeTestTable("posts", cols2),
    });
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"posts\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"tableCount\": 2") != null);
}

test "symbol-index: schema name" {
    const alloc = testing.allocator;
    const ast = ct.makeTestAstWithName("my_schema", &.{});
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"schema\": \"my_schema\"") != null);
}

test "symbol-index: decimal type" {
    const alloc = testing.allocator;
    const col = makeTestColumn("price", .{ .decimal = .{ .precision = 10, .scale = 2 } });
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{col});
    defer alloc.free(cols);
    const table = makeTestTable("products", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try gen.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"decimal(10,2)\"") != null);
}
