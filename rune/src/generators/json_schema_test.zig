const std = @import("std");
const js = @import("json_schema.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");

const testing = std.testing;
const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumn;
const makeTestTable = ct.makeTestTable;
const makeTestTableWithFks = ct.makeTestTableWithFks;
const makeTestAst = ct.makeTestAst;

// ─── Existing type-level tests (kept from v0.48.0) ──────────────

test "json_schema: int column type" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("id", .int);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("{\"type\":\"integer\"}", result);
}

test "json_schema: varchar column type" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("name", .{ .varchar = 64 });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("{\"type\":\"string\",\"maxLength\":64}", result);
}

test "json_schema: boolean column type" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("active", .boolean);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expectEqualStrings("{\"type\":\"boolean\"}", result);
}

test "json_schema: enum column type" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const vals = try alloc.dupe([]const u8, &.{ "active", "inactive", "banned" });
    defer alloc.free(vals);
    const col = makeTestColumn("status", .{ .enum_values = vals });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"enum\":[\"active\",\"inactive\",\"banned\"]") != null);
}

test "json_schema: decimal column type" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("price", .{ .decimal = .{ .precision = 10, .scale = 2 } });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"number\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"multipleOf\"") != null);
}

// ─── Enhanced generate() tests (v0.49.0) ───────────────────────

test "json_schema: generate produces $defs section" {
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
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"$defs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"users\": {") != null);
}

test "json_schema: generate produces $ref for tables" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    // Top-level properties should use $ref
    try testing.expect(std.mem.indexOf(u8, result, "\"$ref\": \"#/$defs/users\"") != null);
}

test "json_schema: generate produces required array for non-nullable columns" {
    const alloc = testing.allocator;
    var not_null_col = makeTestColumn("id", .int);
    not_null_col.flags.nullable = false;
    var nullable_col = makeTestColumn("bio", .text);
    nullable_col.flags.nullable = true;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{ not_null_col, nullable_col });
    defer alloc.free(cols);
    const table = makeTestTable("users", cols);
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    // Table-level required should include "id" but not "bio"
    try testing.expect(std.mem.indexOf(u8, result, "\"required\": [\"id\"]") != null);
}

test "json_schema: generate includes table comment as description" {
    const alloc = testing.allocator;
    const cols = try alloc.dupe(typed_ast.TypedColumn, &.{
        makeTestColumn("id", .int),
    });
    defer alloc.free(cols);
    var table = makeTestTable("users", cols);
    table.comment = "User accounts";
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    defer alloc.free(tables);
    const ast = makeTestAst(tables);
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"description\": \"User accounts\"") != null);
}

test "json_schema: generate with FK produces $ref for referenced table" {
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
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    // FK column should reference users definition
    try testing.expect(std.mem.indexOf(u8, result, "\"$ref\": \"#/$defs/users\"") != null);
}

test "json_schema: generate with no tables produces minimal schema" {
    const alloc = testing.allocator;
    const ast = makeTestAst(&.{});
    const result = try js.generate(alloc, ast, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"$schema\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"object\"") != null);
    // No $defs when no tables
    try testing.expect(std.mem.indexOf(u8, result, "\"$defs\"") == null);
}
