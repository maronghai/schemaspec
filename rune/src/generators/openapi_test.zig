const std = @import("std");
const testing = std.testing;
const openapi = @import("openapi.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");

const Dialect = dialect_enum.Dialect;
const TypedAst = typed_ast.TypedAst;
const TypedTable = typed_ast.TypedTable;
const TypedColumn = typed_ast.TypedColumn;
const TypedView = typed_ast.TypedView;
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;

const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumnWithFlags;
const makeTestTable = ct.makeTestTable;
const makeTestAst = ct.makeTestAstWithName;

// ─── Tests ────────────────────────────────────────────────────

test "basic schema: openapi version and info" {
    const alloc = testing.allocator;
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .nullable = false, .primary_key = true }),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst("myapp", &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"openapi\": \"3.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"title\": \"myapp\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\":") != null);
}

test "field types: integer, string, boolean" {
    const alloc = testing.allocator;
    const cols = [_]TypedColumn{
        makeTestColumn("count", .int, .{}),
        makeTestColumn("name", .{ .varchar = 255 }, .{}),
        makeTestColumn("active", .boolean, .{}),
    };
    const tables = [_]TypedTable{makeTestTable("items", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"integer\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"string\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"boolean\"") != null);
}

test "enum type: enum values array" {
    const alloc = testing.allocator;
    const enum_vals = [_][]const u8{ "active", "inactive", "suspended" };
    var col = makeTestColumn("status", .{ .enum_values = &enum_vals }, .{ .is_enum = true });
    col.default = "'active'";
    const cols = [_]TypedColumn{col};
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"enum\":[\"active\",\"inactive\",\"suspended\"]") != null);
}

test "FK reference: $ref to target table" {
    const alloc = testing.allocator;
    const fks = [_]FkDecl{.{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    }};
    const cols = [_]TypedColumn{
        makeTestColumn("user_id", .int, .{}),
    };
    var table = makeTestTable("orders", &cols);
    table.fks = &fks;
    const tables = [_]TypedTable{ table, makeTestTable("users", &[_]TypedColumn{
        makeTestColumn("id", .int, .{}),
    }) };
    const ast = makeTestAst(null, &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"$ref\": \"#/components/schemas/users\"") != null);
}

test "template inheritance: merged fields" {
    const alloc = testing.allocator;
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .primary_key = true }),
        makeTestColumn("name", .{ .varchar = 255 }, .{}),
        makeTestColumn("email", .{ .varchar = 128 }, .{}),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst("myapp", &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"id\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"email\":") != null);
}

test "multiple tables: all in schemas" {
    const alloc = testing.allocator;
    const users_cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{}),
    };
    const orders_cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{}),
        makeTestColumn("amount", .{ .decimal = .{ .precision = 16, .scale = 2 } }, .{}),
    };
    const tables = [_]TypedTable{
        makeTestTable("users", &users_cols),
        makeTestTable("orders", &orders_cols),
    };
    const ast = makeTestAst("shop", &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"users\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"orders\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"number\"") != null);
}

test "custom type: passthrough resolved" {
    const alloc = testing.allocator;
    const cols = [_]TypedColumn{
        makeTestColumn("id", .uuid, .{}),
    };
    const tables = [_]TypedTable{makeTestTable("accounts", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try openapi.generate(alloc, ast, .pg);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"format\":\"uuid\"") != null);
}

test "nullable fields: not in required" {
    const alloc = testing.allocator;
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .nullable = false }),
        makeTestColumn("name", .{ .varchar = 255 }, .{ .nullable = false }),
        makeTestColumn("bio", .text, .{ .nullable = true }),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try openapi.generate(alloc, ast, .mysql);
    defer alloc.free(result);

    // id and name should be in required, bio should not
    try testing.expect(std.mem.indexOf(u8, result, "\"required\": [\"id\", \"name\"]") != null);
}
