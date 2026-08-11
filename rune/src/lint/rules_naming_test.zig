// Naming rule tests — naming, fk-naming, enum-value-naming, column-boolean-naming,
// timestamp-naming, view-naming.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ast_mod = @import("../types/ast.zig");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

test "lint: camelCase naming detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "userProfiles", &.{
        th.makePkField("id"),
        th.makeField("firstName", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    var table_naming: usize = 0;
    var col_naming: usize = 0;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming")) {
            if (std.mem.indexOf(u8, r.message, "table name") != null) table_naming += 1;
            if (std.mem.indexOf(u8, r.message, "column name") != null) col_naming += 1;
        }
    }
    try testing.expectEqual(@as(usize, 1), table_naming);
    try testing.expectEqual(@as(usize, 1), col_naming);
}

test "lint: FK column without _id suffix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try th.makeTestTable(alloc, "orders", &.{
        th.makePkField("id"),
        th.makeField("user_ref", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const fk = ast_mod.FkDecl{
        .fields = &.{"user_ref"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };
    table.fks = try alloc.dupe(ast_mod.FkDecl, &.{fk});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "fk-naming"));
}

test "lint: FK column with _id suffix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try th.makeTestTable(alloc, "orders", &.{
        th.makePkField("id"),
        th.makeField("user_id", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const fk = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };
    table.fks = try alloc.dupe(ast_mod.FkDecl, &.{fk});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "fk-naming"));
}

test "lint: datetime column with bad naming triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("created", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "timestamp-naming"));
}

test "lint: datetime column with created_at naming passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "timestamp-naming"));
}

test "lint: datetime column with custom _at suffix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("verified_at", .{ .simple = "t" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "timestamp-naming"));
}

test "lint: enum value with lowercase detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .enum_type = &.{ "active", "inactive" } },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAstWithCustomTypes(tables, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "enum-value-naming"));
}

test "lint: enum value in UPPER_CASE passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .enum_type = &.{ "ACTIVE", "INACTIVE" } },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAstWithCustomTypes(tables, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "enum-value-naming"));
}

test "lint: boolean column without is_/has_/can_ prefix triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "column-boolean-naming"));
}

test "lint: boolean column with is_ prefix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("is_active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "column-boolean-naming"));
}

test "lint: boolean column with has_ prefix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("has_subscription", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "column-boolean-naming"));
}

test "lint: view with bad naming triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "user_data",
        .query = "SELECT * FROM users",
        .comment = null,
        .line_no = 1,
    };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = views,
        .sql_comments = &.{},
    };
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "view-naming"));
}

test "lint: view with _view suffix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "user_view",
        .query = "SELECT * FROM users",
        .comment = null,
        .line_no = 1,
    };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = views,
        .sql_comments = &.{},
    };
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "view-naming"));
}

test "lint: view with v_ prefix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "v_users",
        .query = "SELECT * FROM users",
        .comment = null,
        .line_no = 1,
    };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = views,
        .sql_comments = &.{},
    };
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "view-naming"));
}
