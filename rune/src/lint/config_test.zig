const std = @import("std");
const testing = std.testing;
const lint_mod = @import("../lint.zig");
const lintSchema = lint_mod.lintSchema;
const lintDiff = lint_mod.lintDiff;
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../types/ast.zig");

// ─── Shared Test Helpers ───────────────────────────────────────

fn makeTestTable(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field, indexes: []const ast_mod.IndexDecl) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    };
}

fn makeField(name: []const u8, type_info: ast_mod.TypeInfo, modifiers: []const ast_mod.Modifier, fk: ?ast_mod.FkDecl) ast_mod.Field {
    return .{
        .name = name,
        .type_info = type_info,
        .modifiers = modifiers,
        .default_val = null,
        .check = null,
        .fk = fk,
        .comment = null,
        .line_no = 1,
    };
}

fn makePkField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null);
}

fn makeFkField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = "other",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    });
}

fn makeAst(tables: []const ResolvedTable) ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

// ─── Config Toggle Tests ──────────────────────────────────────

test "lint: config toggles work" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "logs", &.{
        makeField("msg", .{ .simple = "s" }, &.{}, null),
        makeField("userId", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);

    // All checks enabled
    const all = try lintSchema(alloc, test_ast, .{});
    try testing.expect(all.items.len >= 2); // no-pk + no-timestamps at minimum

    // Only PK check
    var pk_cfg = lint_mod.LintConfig{};
    pk_cfg.rules.disableAllExcept(.no_pk);
    const pk_only = try lintSchema(alloc, test_ast, pk_cfg);
    var pk_count: usize = 0;
    for (pk_only.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) pk_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), pk_count);
    try testing.expectEqual(@as(usize, 1), pk_only.items.len);
}

test "lint: config toggles new rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "logs", &.{
        makeField("msg", .{ .simple = "s" }, &.{}, null),
        makeField("userId", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);

    // Only wide-table check (should find nothing — table is narrow)
    var wide_cfg = lint_mod.LintConfig{};
    wide_cfg.rules.disableAllExcept(.wide_table);
    const wide_only = try lintSchema(alloc, test_ast, wide_cfg);
    try testing.expectEqual(@as(usize, 0), wide_only.items.len);
}

test "lint: parse rules file" {
    const rules_data =
        \\[lint]
        \\enabled = ["no-pk", "naming"]
        \\disabled = ["no-timestamps"]
        \\
        \\[lint.severity]
        \\no-pk = "error"
        \\
        \\[lint.thresholds]
        \\wide_table_max = 40
        \\count_min = 3
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const rules = try lint_mod.parseLintRules(alloc, rules_data);
    try testing.expect(rules.enabled != null);
    try testing.expectEqual(@as(usize, 2), rules.enabled.?.len);
    try testing.expect(rules.disabled != null);
    try testing.expectEqual(@as(usize, 1), rules.disabled.?.len);
    try testing.expectEqual(@as(usize, 40), rules.thresholds.wide_table_max.?);
    try testing.expectEqual(@as(usize, 3), rules.thresholds.count_min.?);
}

// ─── Diff-Aware Lint Tests ────────────────────────────────────

test "lint: diff detects new issues" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Old: clean schema with PK
    const old_table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const old_tables = try alloc.dupe(ResolvedTable, &.{old_table});
    const old_ast = makeAst(old_tables);
    const old_results = try lintSchema(alloc, old_ast, .{});

    // New: same table but with added FK without index
    const new_table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
        makeFkField("org_id"),
    }, &.{});
    const new_tables = try alloc.dupe(ResolvedTable, &.{new_table});
    const new_ast = makeAst(new_tables);
    const new_results = try lintSchema(alloc, new_ast, .{});

    const diff = try lintDiff(old_results.items, new_results.items, alloc);
    var found_new = false;
    for (diff.added) |r| {
        if (std.mem.eql(u8, r.rule, "no-index-fk")) found_new = true;
    }
    try testing.expect(found_new);
}

test "lint: diff no new issues" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const schema = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{schema});
    const ast1 = makeAst(tables);
    const ast2 = makeAst(tables);
    const r1 = try lintSchema(alloc, ast1, .{});
    const r2 = try lintSchema(alloc, ast2, .{});

    const diff = try lintDiff(r1.items, r2.items, alloc);
    try testing.expectEqual(@as(usize, 0), diff.added.len);
}
