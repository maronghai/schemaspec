// View & enum rule tests — view-select-star, view-no-alias, view-dependency-cycle,
// enum-case, enum-value-duplicate, duplicate-column, orphan-type, custom type diff.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ast_mod = @import("../types/ast.zig");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

// ─── view-select-star tests ───────────────────────────────────

test "lint: view with SELECT * triggers info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT * FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "view-select-star"));
}

test "lint: view with explicit columns passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id, name FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "view-select-star"));
}

test "lint: view with lowercase select * triggers info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "select * from users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "view-select-star"));
}

// ─── view-no-alias tests ─────────────────────────────────────

test "lint: view with AS alias passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id AS user_id FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "view-no-alias"));
}

// ─── view-dependency-cycle tests ─────────────────────────────

test "lint: view cycle detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tables = try alloc.dupe(ResolvedTable, &.{});
    const views = try alloc.dupe(ast_mod.View, &.{
        .{ .name = "view_a", .query = "SELECT * FROM view_b", .comment = null, .line_no = 1 },
        .{ .name = "view_b", .query = "SELECT * FROM view_a", .comment = null, .line_no = 2 },
    });
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = tables, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "view-dependency-cycle"));
}

test "lint: no view cycle passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tables = try alloc.dupe(ResolvedTable, &.{});
    const views = try alloc.dupe(ast_mod.View, &.{
        .{ .name = "view_a", .query = "SELECT * FROM users", .comment = null, .line_no = 1 },
        .{ .name = "view_b", .query = "SELECT * FROM view_a", .comment = null, .line_no = 2 },
    });
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = tables, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "view-dependency-cycle"));
}

// ─── enum tests ──────────────────────────────────────────────

test "lint: non-UPPER_CASE custom type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = th.makeCustomType("statusType");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = th.makeAstWithCustomTypes(&.{}, cts);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "enum-case"));
}

test "lint: UPPER_CASE custom type passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = th.makeCustomType("STATUS_TYPE");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = th.makeAstWithCustomTypes(&.{}, cts);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "enum-case"));
}

test "lint: duplicate enum values triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = ast_mod.CustomType{ .name = "STATUS", .base = .{ .enum_type = &.{ "ACTIVE", "INACTIVE", "ACTIVE" } }, .dialect_overrides = &.{}, .line_no = 1 };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = th.makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "enum-value-duplicate"));
}

test "lint: unique enum values passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = ast_mod.CustomType{ .name = "STATUS", .base = .{ .enum_type = &.{ "ACTIVE", "INACTIVE", "PENDING" } }, .dialect_overrides = &.{}, .line_no = 1 };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = th.makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "enum-value-duplicate"));
}

// ─── orphan-type tests ───────────────────────────────────────

test "lint: orphan type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = th.makeCustomType("STATUS_TYPE");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAstWithCustomTypes(tables, cts);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "orphan-type"));
}

test "lint: used type passes orphan check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ct = th.makeCustomType("status");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("status", .{ .simple = "status" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAstWithCustomTypes(tables, cts);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "orphan-type"));
}

// ─── duplicate-column tests ──────────────────────────────────

test "lint: duplicate column name triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s100" }, &.{}, null), th.makeField("name", .{ .simple = "s50" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "duplicate-column"));
}

test "lint: no duplicate column names passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s100" }, &.{}, null), th.makeField("email", .{ .simple = "s100" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "duplicate-column"));
}

// ─── custom type diff tests ──────────────────────────────────

test "custom type diff: detects added types" {
    const diff_engine = @import("../diff/engine.zig");
    const resolved_ast_mod = @import("../types/resolved_ast.zig");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const old = resolved_ast_mod.ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = &.{}, .sql_comments = &.{} };
    const new_ct = ast_mod.CustomType{ .name = "STATUS", .base = .{ .simple = "s" }, .dialect_overrides = &.{}, .line_no = 1 };
    const new = resolved_ast_mod.ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = try alloc.dupe(ast_mod.CustomType, &.{new_ct}), .tables = &.{}, .views = &.{}, .sql_comments = &.{} };
    const result = try diff_engine.diff(old, new, alloc);
    try testing.expectEqual(@as(usize, 1), result.custom_type_diffs.len);
    try testing.expect(result.custom_type_diffs[0].action == .add);
    try testing.expectEqualStrings("STATUS", result.custom_type_diffs[0].name);
}

test "custom type diff: detects dropped types" {
    const diff_engine = @import("../diff/engine.zig");
    const resolved_ast_mod = @import("../types/resolved_ast.zig");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const old_ct = ast_mod.CustomType{ .name = "STATUS", .base = .{ .simple = "s" }, .dialect_overrides = &.{}, .line_no = 1 };
    const old = resolved_ast_mod.ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = try alloc.dupe(ast_mod.CustomType, &.{old_ct}), .tables = &.{}, .views = &.{}, .sql_comments = &.{} };
    const new = resolved_ast_mod.ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = &.{}, .sql_comments = &.{} };
    const result = try diff_engine.diff(old, new, alloc);
    try testing.expectEqual(@as(usize, 1), result.custom_type_diffs.len);
    try testing.expect(result.custom_type_diffs[0].action == .drop);
    try testing.expectEqualStrings("STATUS", result.custom_type_diffs[0].name);
}


// ─── view-no-comment tests ──────────────────────────────────

test "lint: view without comment triggers note" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "view-no-comment"));
}

test "lint: view with comment passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id FROM users", .comment = "Active users", .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "view-no-comment"));
}

test "lint: view-no-comment respects include_views flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    // include_views defaults to false
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "view-no-comment"));
}

// ─── view-name-too-long tests ───────────────────────────────

test "lint: view with over-long name triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "view-name-too-long"));
}

test "lint: view with short name passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const view = ast_mod.View{ .name = "user_view", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };
    const views = try alloc.dupe(ast_mod.View, &.{view});
    const test_ast = ResolvedAst{ .schema_name = null, .schema_charset = null, .custom_types = &.{}, .tables = &.{}, .views = views, .sql_comments = &.{} };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lint_mod.lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "view-name-too-long"));
}

// ─── enum-value-too-long tests ──────────────────────────────

test "lint: enum value with over-long name triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // 70-char enum value exceeds the default column_name_max (64)
    const long_value = "this_enum_value_name_is_definitely_way_too_long_to_be_allowed_here";
    try testing.expect(long_value.len > 64);
    const ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .enum_type = &.{long_value} },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = th.makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(th.findRule(results, "enum-value-too-long"));
}

test "lint: enum value with short name passes length check" {
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
    const test_ast = th.makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lint_mod.lintSchema(alloc, test_ast, .{});
    try testing.expect(!th.findRule(results, "enum-value-too-long"));
}
