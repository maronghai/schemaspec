const std = @import("std");
const testing = std.testing;
const graphql = @import("graphql.zig");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");

const Dialect = dialect_enum.Dialect;
const TypedAst = typed_ast.TypedAst;
const TypedTable = typed_ast.TypedTable;
const TypedColumn = typed_ast.TypedColumn;
const TypedView = typed_ast.TypedView;
const FkDecl = ast_mod.FkDecl;

const ct = @import("common_test.zig");
const makeTestColumn = ct.makeTestColumnWithFlags;
const makeTestTable = ct.makeTestTable;
const makeTestAst = ct.makeTestAstWithName;

// ─── Tests ────────────────────────────────────────────────────

test "basic type mapping: int, string, boolean" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cols = [_]TypedColumn{
        makeTestColumn("count", .int, .{}),
        makeTestColumn("name", .{ .varchar = 255 }, .{}),
        makeTestColumn("active", .boolean, .{}),
    };
    const tables = [_]TypedTable{makeTestTable("items", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    try testing.expect(std.mem.indexOf(u8, result, "count: Int!") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name: String!") != null);
    try testing.expect(std.mem.indexOf(u8, result, "active: Boolean!") != null);
}

test "nullable fields: no exclamation mark" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .nullable = false, .primary_key = true }),
        makeTestColumn("bio", .text, .{ .nullable = true }),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    // Primary key named "id" → ID type, nullable (no !)
    try testing.expect(std.mem.indexOf(u8, result, "id: ID") != null);
    // Nullable text → no !
    try testing.expect(std.mem.indexOf(u8, result, "bio: String\n") != null);
}

test "enum column: generates enum type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const enum_vals = [_][]const u8{ "active", "inactive", "suspended" };
    var col = makeTestColumn("status", .{ .enum_values = &enum_vals }, .{});
    col.flags.is_enum = true;
    col.flags.nullable = false;
    col.enum_values = &enum_vals;
    const cols = [_]TypedColumn{col};
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    // Should have enum type definition
    try testing.expect(std.mem.indexOf(u8, result, "enum statusType {") != null);
    try testing.expect(std.mem.indexOf(u8, result, "  active") != null);
    try testing.expect(std.mem.indexOf(u8, result, "  inactive") != null);
    try testing.expect(std.mem.indexOf(u8, result, "  suspended") != null);
    // Field should reference the enum type (non-nullable)
    try testing.expect(std.mem.indexOf(u8, result, "status: statusType!") != null);
}

test "FK column: Int type with relation field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
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
    const tables = [_]TypedTable{table};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    // FK column → Int type
    try testing.expect(std.mem.indexOf(u8, result, "user_id: Int!") != null);
    // Relation field
    try testing.expect(std.mem.indexOf(u8, result, "user: users") != null);
}

test "query and mutation types generated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .primary_key = true }),
        makeTestColumn("name", .{ .varchar = 255 }, .{}),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    // Query type
    try testing.expect(std.mem.indexOf(u8, result, "type Query {") != null);
    try testing.expect(std.mem.indexOf(u8, result, "user(id: ID!): users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "usersList(limit: Int, offset: Int): [users!]!") != null);

    // Mutation type — PascalCase singular strips trailing 's'
    try testing.expect(std.mem.indexOf(u8, result, "type Mutation {") != null);
    try testing.expect(std.mem.indexOf(u8, result, "createUser(input: usersInput!): User!") != null);
    try testing.expect(std.mem.indexOf(u8, result, "updateUser(id: ID!, input: usersInput!): User!") != null);
    try testing.expect(std.mem.indexOf(u8, result, "deleteUser(id: ID!): Boolean!") != null);
}

test "input type: skips auto-generated fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cols = [_]TypedColumn{
        makeTestColumn("id", .int, .{ .primary_key = true, .auto_increment = true }),
        makeTestColumn("name", .{ .varchar = 255 }, .{}),
        makeTestColumn("created_at", .datetime, .{ .has_timestamp_default = true }),
    };
    const tables = [_]TypedTable{makeTestTable("users", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    // Input type should exist
    try testing.expect(std.mem.indexOf(u8, result, "input usersInput {") != null);
    // id (auto_increment) should be skipped
    try testing.expect(std.mem.indexOf(u8, result, "usersInput {") != null);
    // name should be present
    try testing.expect(std.mem.indexOf(u8, result, "  name: String!") != null);
}

test "empty schema: no query or mutation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ast = makeTestAst(null, &.{});

    const result = try graphql.generate(alloc, ast, .mysql);

    // Should have no Query or Mutation
    try testing.expect(std.mem.indexOf(u8, result, "type Query") == null);
    try testing.expect(std.mem.indexOf(u8, result, "type Mutation") == null);
}

test "view: read-only type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const views = [_]TypedView{.{
        .name = "user_summary",
        .query = "SELECT id, name FROM users",
        .comment = null,
        .line_no = 1,
    }};
    var ast = makeTestAst(null, &.{});
    ast.views = &views;

    const result = try graphql.generate(alloc, ast, .mysql);

    // View type
    try testing.expect(std.mem.indexOf(u8, result, "type user_summary {") != null);
    // View query field in Query type
    try testing.expect(std.mem.indexOf(u8, result, "user_summary: [user_summary!]!") != null);
    // No mutations for views
    try testing.expect(std.mem.indexOf(u8, result, "createUser_summary") == null);
}

test "datetime: custom scalar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cols = [_]TypedColumn{
        makeTestColumn("created_at", .datetime, .{ .is_datetime = true }),
    };
    const tables = [_]TypedTable{makeTestTable("events", &cols)};
    const ast = makeTestAst(null, &tables);

    const result = try graphql.generate(alloc, ast, .mysql);

    try testing.expect(std.mem.indexOf(u8, result, "scalar DateTime") != null);
    try testing.expect(std.mem.indexOf(u8, result, "created_at: DateTime!") != null);
}
