const std = @import("std");
const testing = std.testing;
const lint_mod = @import("lint.zig");
const lintSchema = lint_mod.lintSchema;
const lintDiff = lint_mod.lintDiff;
const LintConfig = lint_mod.LintConfig;
const ResolvedAst = @import("types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("types/ast.zig");

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

fn makeIndex(name: []const u8, kind: ast_mod.IndexType, fields: []const []const u8) ast_mod.IndexDecl {
    return .{
        .kind = kind,
        .name = name,
        .fields = fields,
        .descending = &.{},
        .line_no = 1,
    };
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

fn makeAstWithCustomTypes(tables: []const ResolvedTable, custom_types: []const ast_mod.CustomType) ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = custom_types,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

fn makeCustomType(name: []const u8) ast_mod.CustomType {
    return .{
        .name = name,
        .base = .{ .simple = name },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
}

fn makeSimpleField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "s" }, &.{}, null);
}

// ─── Tests ────────────────────────────────────────────────────

test "lint: clean schema passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    table.comment = "User accounts";
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    try testing.expectEqual(@as(usize, 0), results.items.len);
}

test "lint: no PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "logs", &.{
        makeField("msg", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) found = true;
    }
    try testing.expect(found);
}

test "lint: composite PK via index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "order_items", &.{
        makeField("order_id", .{ .simple = "n" }, &.{}, null),
        makeField("product_id", .{ .simple = "n" }, &.{}, null),
    }, &.{
        makeIndex("pk_order_items", .primary_key, &.{ "order_id", "product_id" }),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found_pk = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) found_pk = true;
    }
    try testing.expect(!found_pk);
}

test "lint: camelCase naming detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "userProfiles", &.{
        makePkField("id"),
        makeField("firstName", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
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

test "lint: FK without index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkField("user_id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-index-fk")) found = true;
    }
    try testing.expect(found);
}

test "lint: FK with index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkField("user_id"),
    }, &.{
        makeIndex("idx_user_id", .regular, &.{"user_id"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-index-fk")) {
            try testing.expect(false);
        }
    }
}

test "lint: no timestamps detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-timestamps")) found = true;
    }
    try testing.expect(found);
}

test "lint: timestamps present passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
        makeField("updated_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-timestamps")) {
            try testing.expect(false);
        }
    }
}

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
    const pk_only = try lintSchema(alloc, test_ast, .{ .check_naming = false, .check_fk_index = false, .check_timestamps = false, .check_empty_table = false, .check_table_comment = false });
    var pk_count: usize = 0;
    for (pk_only.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) pk_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), pk_count);
    try testing.expectEqual(@as(usize, 1), pk_only.items.len);
}

test "lint: JSON output format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "logs", &.{
        makeField("msg", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    const json = try lint_mod.formatLintJson(alloc, results.items);
    try testing.expect(std.mem.indexOf(u8, json, "\"issues\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"no-pk\"") != null);
}

// ─── Wide Table Tests ─────────────────────────────────────────

test "lint: wide table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a table with 35 fields (exceeds default threshold of 30)
    var fields: [35]ast_mod.Field = undefined;
    for (0..35) |i| {
        var buf: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "col_{d}", .{i}) catch "col";
        fields[i] = makeSimpleField(name);
    }
    const table = try makeTestTable(alloc, "wide_table", &fields, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "wide-table")) found = true;
    }
    try testing.expect(found);
}

test "lint: narrow table passes wide check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{ .check_pk = false, .check_naming = false, .check_fk_index = false, .check_timestamps = false });
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "wide-table")) {
            try testing.expect(false);
        }
    }
}

// ─── Enum Case Tests ──────────────────────────────────────────

test "lint: non-UPPER_CASE custom type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = makeCustomType("statusType");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = makeAstWithCustomTypes(&.{}, cts);
    const results = try lintSchema(alloc, test_ast, .{ .check_pk = false, .check_naming = false, .check_fk_index = false, .check_timestamps = false });
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-case")) found = true;
    }
    try testing.expect(found);
}

test "lint: UPPER_CASE custom type passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = makeCustomType("STATUS_TYPE");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = makeAstWithCustomTypes(&.{}, cts);
    const results = try lintSchema(alloc, test_ast, .{ .check_pk = false, .check_naming = false, .check_fk_index = false, .check_timestamps = false });
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-case")) {
            try testing.expect(false);
        }
    }
}

// ─── Count Tests ──────────────────────────────────────────────

test "lint: low field count detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Table with only PK + 0 non-PK fields
    const table = try makeTestTable(alloc, "empty_table", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{ .check_pk = false, .check_naming = false, .check_fk_index = false, .check_timestamps = false });
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "count")) found = true;
    }
    try testing.expect(found);
}

test "lint: sufficient field count passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
        makeSimpleField("email"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{ .check_pk = false, .check_naming = false, .check_fk_index = false, .check_timestamps = false });
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "count")) {
            try testing.expect(false);
        }
    }
}

// ─── SARIF Output Tests ───────────────────────────────────────

test "lint: SARIF output format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "logs", &.{
        makeField("msg", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    const sarif = try lint_mod.formatLintSarif(alloc, results.items, "0.137.0", "test.ss");
    try testing.expect(std.mem.indexOf(u8, sarif, "\"version\":\"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"tool\"") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"results\"") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"no-pk\"") != null);
}

test "lint: SARIF empty results" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    table.comment = "User accounts";
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    const sarif = try lint_mod.formatLintSarif(alloc, results.items, "0.137.0", null);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"results\":[]") != null);
}

// ─── Diff-Aware Lint Tests ────────────────────────────────────

test "lint: diff detects new issues" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Old: clean schema with PK
    const old_table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const old_tables = try alloc.dupe(ResolvedTable, &.{old_table});
    const old_ast = makeAst(old_tables);
    const old_results = try lintSchema(alloc, old_ast, .{});

    // New: same table but with added FK without index
    const new_table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
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
        makeSimpleField("name"),
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

// ─── Lint Config Tests ────────────────────────────────────────

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
    const wide_only = try lintSchema(alloc, test_ast, .{
        .check_pk = false,
        .check_naming = false,
        .check_fk_index = false,
        .check_timestamps = false,
        .check_enum_case = false,
        .check_count = false,
        .check_fk_cascade = false,
        .check_nullable_pk = false,
        .check_orphan_type = false,
        .check_index_unused = false,
        .check_circular_fk = false,
        .check_duplicate_index = false,
        .check_empty_table = false,
        .check_table_comment = false,
    });
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

// ─── FK Cascade Tests ────────────────────────────────────────

fn makeFkFieldWithActions(name: []const u8, actions: []const ast_mod.FkAction) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = "other",
        .ref_fields = &.{"id"},
        .actions = actions,
        .line_no = 1,
    });
}

test "lint: FK without cascade actions detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkField("user_id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-cascade")) found = true;
    }
    try testing.expect(found);
}

test "lint: FK with both cascade actions passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const actions = [_]ast_mod.FkAction{
        .{ .trigger = .on_delete, .action = .cascade },
        .{ .trigger = .on_update, .action = .cascade },
    };
    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkFieldWithActions("user_id", &actions),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-cascade")) {
            try testing.expect(false);
        }
    }
}

test "lint: FK with only ON DELETE detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const actions = [_]ast_mod.FkAction{
        .{ .trigger = .on_delete, .action = .cascade },
    };
    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkFieldWithActions("user_id", &actions),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-cascade") and std.mem.indexOf(u8, r.message, "ON UPDATE") != null) found = true;
    }
    try testing.expect(found);
}

// ─── Nullable PK Tests ───────────────────────────────────────

test "lint: nullable PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } }, null),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "nullable-pk")) found = true;
    }
    try testing.expect(found);
}

test "lint: non-nullable PK passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "nullable-pk")) {
            try testing.expect(false);
        }
    }
}

// ─── Orphan Type Tests ───────────────────────────────────────

test "lint: orphan type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Custom type defined but not used by any table field
    const ct = makeCustomType("STATUS_TYPE");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAstWithCustomTypes(tables, cts);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "orphan-type")) found = true;
    }
    try testing.expect(found);
}

test "lint: used type passes orphan check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Custom type IS used by a table field
    const ct = makeCustomType("status");
    const cts = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("status", .{ .simple = "status" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAstWithCustomTypes(tables, cts);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "orphan-type")) {
            try testing.expect(false);
        }
    }
}

// ─── Index Unused Tests ───────────────────────────────────────

test "lint: unused index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Index on a column that is not an FK field
    const idx = makeIndex("idx_name", .regular, &.{"name"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-unused")) found = true;
    }
    try testing.expect(found);
}

test "lint: FK-covered index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Index on an FK column — should NOT trigger index-unused
    const idx = makeIndex("idx_user_id", .regular, &.{"user_id"});
    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkField("user_id"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-unused")) {
            try testing.expect(false);
        }
    }
}

test "lint: unique index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Unique index — always useful, never triggers index-unused
    const idx = makeIndex("idx_email", .unique, &.{"email"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("email"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-unused")) {
            try testing.expect(false);
        }
    }
}

// ─── Circular FK Tests ────────────────────────────────────────

test "lint: circular FK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A -> B -> A circular chain
    const table_a = try makeTestTableWithFks(alloc, "a", &.{
        makePkField("id"),
        makeFkFieldTo("b_id", "b", "id"),
    });
    const table_b = try makeTestTableWithFks(alloc, "b", &.{
        makePkField("id"),
        makeFkFieldTo("a_id", "a", "id"),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_b });
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "circular-fk")) found = true;
    }
    try testing.expect(found);
}

test "lint: no circular FK passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A -> B -> C (no cycle)
    const table_a = try makeTestTableWithFks(alloc, "a", &.{
        makePkField("id"),
        makeFkFieldTo("b_id", "b", "id"),
    });
    const table_b = try makeTestTableWithFks(alloc, "b", &.{
        makePkField("id"),
        makeFkFieldTo("c_id", "c", "id"),
    });
    const table_c = try makeTestTableWithFks(alloc, "c", &.{
        makePkField("id"),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_b, table_c });
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "circular-fk")) {
            try testing.expect(false);
        }
    }
}

// ─── Helper for FK tables ─────────────────────────────────────

fn makeFkFieldTo(name: []const u8, ref_table: []const u8, ref_field: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = ref_table,
        .ref_fields = &.{ref_field},
        .actions = &.{},
        .line_no = 1,
    });
}

fn makeTestTableWithFks(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

// ─── Duplicate Index Tests ─────────────────────────────────────

test "lint: duplicate index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Two indexes on the same columns with the same kind
    const idx1 = makeIndex("idx_name", .regular, &.{"name"});
    const idx2 = makeIndex("idx_name_2", .regular, &.{"name"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{ idx1, idx2 });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "duplicate-index")) found = true;
    }
    try testing.expect(found);
}

test "lint: no duplicate index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Two indexes on different columns — not duplicates
    const idx1 = makeIndex("idx_name", .regular, &.{"name"});
    const idx2 = makeIndex("idx_email", .regular, &.{"email"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
        makeSimpleField("email"),
    }, &.{ idx1, idx2 });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "duplicate-index")) {
            try testing.expect(false);
        }
    }
}

test "lint: different index kinds are not duplicates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Same columns but different kinds (regular vs unique) — not duplicates
    const idx1 = makeIndex("idx_name", .regular, &.{"name"});
    const idx2 = makeIndex("uniq_name", .unique, &.{"name"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{ idx1, idx2 });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "duplicate-index")) {
            try testing.expect(false);
        }
    }
}

test "lint: empty table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Table with zero fields
    const table = try makeTestTable(alloc, "empty_table", &.{}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "empty-table")) found = true;
    }
    try testing.expect(found);
}

test "lint: non-empty table passes empty-table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "empty-table")) {
            try testing.expect(false);
        }
    }
}

test "lint: table without comment detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Table with no comment
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-comment")) found = true;
    }
    try testing.expect(found);
}

test "lint: table with comment passes table-comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    table.comment = "User accounts table";
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-comment")) {
            try testing.expect(false);
        }
    }
}
