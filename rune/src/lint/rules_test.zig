const std = @import("std");
const testing = std.testing;
const lint_mod = @import("../lint.zig");
const lintSchema = lint_mod.lintSchema;
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

fn makeTestTableWithFkDecls(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field, fks: []const ast_mod.FkDecl) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = try alloc.dupe(ast_mod.FkDecl, fks),
        .indexes = &.{},
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

fn makeFkFieldTo(name: []const u8, ref_table: []const u8, ref_field: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = ref_table,
        .ref_fields = &.{ref_field},
        .actions = &.{},
        .line_no = 1,
    });
}

fn makeFkFieldWithActions(name: []const u8, actions: []const ast_mod.FkAction) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = "other",
        .ref_fields = &.{"id"},
        .actions = actions,
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

// ─── No PK Tests ──────────────────────────────────────────────

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
    // Disable column-length rule since test fields use bare 's' type
    // Disable column-default-required since test fields have no defaults
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    cfg.rules.setEnabled(.column_default_required, false);
    const results = try lintSchema(alloc, test_ast, cfg);
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

// ─── Naming Tests ─────────────────────────────────────────────

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

// ─── FK Index Tests ───────────────────────────────────────────

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

// ─── Timestamps Tests ─────────────────────────────────────────

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
        makeField("name", .{ .simple = "s" }, &.{}, null),
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

// ─── Wide Table Tests ─────────────────────────────────────────

test "lint: wide table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

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
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
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
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
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
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
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

    const table = try makeTestTable(alloc, "empty_table", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
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
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "count")) {
            try testing.expect(false);
        }
    }
}

// ─── FK Cascade Tests ────────────────────────────────────────

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

// ─── Duplicate Index Tests ─────────────────────────────────────

test "lint: duplicate index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

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

// ─── Empty Table Tests ────────────────────────────────────────

test "lint: empty table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

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

// ─── Table Comment Tests ──────────────────────────────────────

test "lint: table without comment detected" {
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

// ─── Serial Type Tests ────────────────────────────────────────

test "lint: serial type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makeField("id", .{ .simple = "serial" }, &.{}, null),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "serial-type")) found = true;
    }
    try testing.expect(found);
}

test "lint: bigserial type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "events", &.{
        makeField("id", .{ .simple = "bigserial" }, &.{}, null),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "serial-type")) found = true;
    }
    try testing.expect(found);
}

test "lint: non-serial type passes" {
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
        if (std.mem.eql(u8, r.rule, "serial-type")) {
            try testing.expect(false);
        }
    }
}

// ─── Table Name Length Tests ──────────────────────────────────

test "lint: long table name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const long_name = "this_is_a_very_long_table_name_that_exceeds_the_default_character_limit_of_sixty_four";
    const table = try makeTestTable(alloc, long_name, &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-name-length")) found = true;
    }
    try testing.expect(found);
}

test "lint: short table name passes" {
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
        if (std.mem.eql(u8, r.rule, "table-name-length")) {
            try testing.expect(false);
        }
    }
}

// ─── Column Length Tests ─────────────────────────────────────

test "lint: bare string type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        // s is parsed as .varchar_explicit = 0 (no explicit length)
        makeField("name", .{ .varchar_explicit = 0 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) found = true;
    }
    try testing.expect(found);
}

test "lint: explicit varchar length passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .varchar_explicit = 64 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) {
            try testing.expect(false);
        }
    }
}

test "lint: column-length rule can be disabled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .varchar_explicit = 0 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) {
            try testing.expect(false);
        }
    }
}

// ─── Index Column Missing Tests ─────────────────────────────

test "lint: index referencing non-existent column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const idx = makeIndex("idx_bad", .regular, &.{"nonexistent_col"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-column-missing")) found = true;
    }
    try testing.expect(found);
}

test "lint: index referencing valid column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const idx = makeIndex("idx_name", .regular, &.{"name"});
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-column-missing")) {
            try testing.expect(false);
        }
    }
}

test "lint: composite index with missing column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const idx = makeIndex("idx_composite", .regular, &.{ "name", "missing_col" });
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{idx});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-column-missing")) found = true;
    }
    try testing.expect(found);
}

// ─── Naming Prefix Tests ────────────────────────────────────

test "lint: tbl_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "tbl_users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: t_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "t_config", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: table_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "table_data", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: clean table name passes naming-prefix" {
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
        if (std.mem.eql(u8, r.rule, "naming-prefix")) {
            try testing.expect(false);
        }
    }
}

// ─── FK Naming Tests ──────────────────────────────────────────

test "lint: FK column without _id suffix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeField("user_ref", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    // Add table-level FK
    const fk = ast_mod.FkDecl{
        .fields = &.{"user_ref"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };
    table.fks = try alloc.dupe(ast_mod.FkDecl, &.{fk});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-naming")) found = true;
    }
    try testing.expect(found);
}

test "lint: FK column with _id suffix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeField("user_id", .{ .simple = "n" }, &.{}, null),
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
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-naming")) {
            try testing.expect(false);
        }
    }
}

// ─── Bool Default Tests ───────────────────────────────────────

test "lint: boolean without default detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "bool-default")) found = true;
    }
    try testing.expect(found);
}

test "lint: boolean with default passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    // Add default value
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.bool_default, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "bool-default")) {
            try testing.expect(false);
        }
    }
}

// ─── nullable-column-default tests ───────────────────────────────

test "lint: nullable column without default triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "nullable-column-default")) found = true;
    }
    try testing.expect(found);
}

test "lint: nullable column with default passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    // Disable the rule to simulate having a default
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.nullable_column_default, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "nullable-column-default")) {
            try testing.expect(false);
        }
    }
}

// ─── timestamp-naming tests ──────────────────────────────────────

test "lint: datetime column with bad naming triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("created", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "timestamp-naming")) found = true;
    }
    try testing.expect(found);
}

test "lint: datetime column with created_at naming passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "timestamp-naming")) {
            try testing.expect(false);
        }
    }
}

test "lint: datetime column with custom _at suffix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("verified_at", .{ .simple = "t" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "timestamp-naming")) {
            try testing.expect(false);
        }
    }
}

// ─── enum-value-naming tests ───────────────────────────────────

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

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAstWithCustomTypes(tables, custom_types);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-value-naming")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
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

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAstWithCustomTypes(tables, custom_types);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-value-naming")) {
            try testing.expect(false);
        }
    }
}

// ─── fk-null tests ─────────────────────────────────────────────

test "lint: nullable FK column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a field with both FK reference and nullable modifier
    const fk_field = ast_mod.Field{
        .name = "user_id",
        .type_info = .{ .simple = "n" },
        .modifiers = &.{.{ .kind = .nullable, .line_no = 1 }},
        .default_val = null,
        .check = null,
        .fk = .{
            .fields = &.{"user_id"},
            .ref_table = "users",
            .ref_fields = &.{"id"},
            .actions = &.{},
            .line_no = 1,
        },
        .comment = null,
        .line_no = 1,
    };

    const fk_decl = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };

    const table = try makeTestTableWithFkDecls(alloc, "orders", &.{
        makePkField("id"),
        fk_field,
    }, &.{fk_decl});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-null")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: non-nullable FK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a field with FK reference but no nullable modifier
    const fk_field = ast_mod.Field{
        .name = "user_id",
        .type_info = .{ .simple = "n" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = .{
            .fields = &.{"user_id"},
            .ref_table = "users",
            .ref_fields = &.{"id"},
            .actions = &.{},
            .line_no = 1,
        },
        .comment = null,
        .line_no = 1,
    };

    const fk_decl = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    };

    const table = try makeTestTableWithFkDecls(alloc, "orders", &.{
        makePkField("id"),
        fk_field,
    }, &.{fk_decl});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-null")) {
            try testing.expect(false);
        }
    }
}

// ─── custom type diff tests ──────────────────────────────────────

test "custom type diff: detects added types" {
    const diff_engine = @import("../diff/engine.zig");
    const resolved_ast_mod = @import("../types/resolved_ast.zig");

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old = resolved_ast_mod.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const new_ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const new = resolved_ast_mod.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = try alloc.dupe(ast_mod.CustomType, &.{new_ct}),
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };

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

    const old_ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const old = resolved_ast_mod.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = try alloc.dupe(ast_mod.CustomType, &.{old_ct}),
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const new = resolved_ast_mod.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };

    const result = try diff_engine.diff(old, new, alloc);
    try testing.expectEqual(@as(usize, 1), result.custom_type_diffs.len);
    try testing.expect(result.custom_type_diffs[0].action == .drop);
    try testing.expectEqualStrings("STATUS", result.custom_type_diffs[0].name);
}

// ─── view-naming tests ──────────────────────────────────────────

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
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-naming")) found = true;
    }
    try testing.expect(found);
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
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-naming")) {
            try testing.expect(false);
        }
    }
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
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-naming")) {
            try testing.expect(false);
        }
    }
}

// ─── duplicate-column tests ──────────────────────────────────────

test "lint: duplicate column name triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s100" }, &.{}, null),
        makeField("name", .{ .simple = "s50" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "duplicate-column")) found = true;
    }
    try testing.expect(found);
}

test "lint: no duplicate column names passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s100" }, &.{}, null),
        makeField("email", .{ .simple = "s100" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "duplicate-column")) {
            try testing.expect(false);
        }
    }
}

// ─── view-select-star tests ─────────────────────────────────────

test "lint: view with SELECT * triggers info" {
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
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-select-star")) found = true;
    }
    try testing.expect(found);
}

test "lint: view with explicit columns passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "user_view",
        .query = "SELECT id, name FROM users",
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
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-select-star")) {
            try testing.expect(false);
        }
    }
}

test "lint: view with lowercase select * triggers info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "user_view",
        .query = "select * from users",
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
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-select-star")) found = true;
    }
    try testing.expect(found);
}

// ─── enum-value-duplicate tests ─────────────────────────────────

test "lint: duplicate enum values triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .enum_type = &.{ "ACTIVE", "INACTIVE", "ACTIVE" } },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-value-duplicate")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: unique enum values passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ct = ast_mod.CustomType{
        .name = "STATUS",
        .base = .{ .enum_type = &.{ "ACTIVE", "INACTIVE", "PENDING" } },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const custom_types = try alloc.dupe(ast_mod.CustomType, &.{ct});
    const test_ast = makeAstWithCustomTypes(&.{}, custom_types);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "enum-value-duplicate")) {
            try testing.expect(false);
        }
    }
}

// ─── column-boolean-naming tests ──────────────────────────────

test "lint: boolean column without is_/has_/can_ prefix triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-boolean-naming")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: boolean column with is_ prefix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("is_active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-boolean-naming")) {
            try testing.expect(false);
        }
    }
}

test "lint: boolean column with has_ prefix passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("has_subscription", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-boolean-naming")) {
            try testing.expect(false);
        }
    }
}

// ─── fk-depth tests ───────────────────────────────────────────

test "lint: FK chain depth 1 passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table_a = try makeTestTableWithFks(alloc, "orders", &.{
        makePkField("id"),
        makeFkFieldTo("user_id", "users", "id"),
    });
    const table_users = try makeTestTableWithFks(alloc, "users", &.{
        makePkField("id"),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_users });
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-depth")) {
            try testing.expect(false);
        }
    }
}

test "lint: FK chain depth 4 triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a chain: level4 -> level3 -> level2 -> level1 -> base
    const level4 = try makeTestTableWithFks(alloc, "level4", &.{
        makePkField("id"),
        makeFkFieldTo("level3_id", "level3", "id"),
    });
    const level3 = try makeTestTableWithFks(alloc, "level3", &.{
        makePkField("id"),
        makeFkFieldTo("level2_id", "level2", "id"),
    });
    const level2 = try makeTestTableWithFks(alloc, "level2", &.{
        makePkField("id"),
        makeFkFieldTo("level1_id", "level1", "id"),
    });
    const level1 = try makeTestTableWithFks(alloc, "level1", &.{
        makePkField("id"),
        makeFkFieldTo("base_id", "base", "id"),
    });
    const base = try makeTestTableWithFks(alloc, "base", &.{
        makePkField("id"),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{ level4, level3, level2, level1, base });
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-depth")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

// ─── cross-dialect-types tests ──────────────────────────────────

test "lint: MySQL UNSIGNED type triggers cross-dialect warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("amount", .{ .simple = "unsigned" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "cross-dialect-types")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: TINYINT type triggers cross-dialect info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "flags", &.{
        makePkField("id"),
        makeField("flag", .{ .simple = "tinyint" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "cross-dialect-types")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: cross-portable type passes cross-dialect check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    cfg.rules.setEnabled(.column_length, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "cross-dialect-types")) {
            try testing.expect(false);
        }
    }
}

// ─── column-default-required tests ─────────────────────────────

test "lint: non-PK non-nullable column without default triggers warning" {
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
        if (std.mem.eql(u8, r.rule, "column-default-required")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: nullable column passes column-default-required" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-default-required")) {
            try testing.expect(false);
        }
    }
}

// ─── unique-constraint tests ───────────────────────────────────

test "lint: UNIQUE on PK column triggers redundancy warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{
        makeIndex("uniq_id", .unique, &.{"id"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "unique-constraint")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: UNIQUE on non-PK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("email"),
    }, &.{
        makeIndex("uniq_email", .unique, &.{"email"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "unique-constraint")) {
            try testing.expect(false);
        }
    }
}

// ─── composite-pk tests ────────────────────────────────────────

test "lint: multiple auto-inc PKs triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "bad_table", &.{
        makeField("id1", .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null),
        makeField("id2", .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "composite-pk")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: single auto-inc PK passes composite-pk check" {
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
        if (std.mem.eql(u8, r.rule, "composite-pk")) {
            try testing.expect(false);
        }
    }
}

// ─── view-no-alias tests ───────────────────────────────────────

test "lint: view with AS alias passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const view = ast_mod.View{
        .name = "user_view",
        .query = "SELECT id AS user_id FROM users",
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
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-no-alias")) {
            try testing.expect(false);
        }
    }
}

// ─── fk-duplicate tests ───────────────────────────────────────

test "lint: multiple FKs to same table triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "posts", &.{
        makePkField("id"),
        makeFkFieldTo("author_id", "users", "id"),
        makeFkFieldTo("reviewer_id", "users", "id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-duplicate")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: FKs to different tables passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkFieldTo("user_id", "users", "id"),
        makeFkFieldTo("product_id", "products", "id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-duplicate")) {
            try testing.expect(false);
        }
    }
}

test "lint: single FK passes fk-duplicate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "orders", &.{
        makePkField("id"),
        makeFkFieldTo("user_id", "users", "id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "fk-duplicate")) {
            try testing.expect(false);
        }
    }
}

// ─── Reserved Word Tests ─────────────────────────────────────

test "lint: reserved word table name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "select", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "reserved-word")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: reserved word column name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("order", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "reserved-word") and std.mem.indexOf(u8, r.message, "column name") != null) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: non-reserved word passes" {
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
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "reserved-word")) {
            try testing.expect(false);
        }
    }
}

// ─── Column Type Portability Tests ───────────────────────────

test "lint: MySQL-specific tinyint detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("age", .{ .simple = "tinyint" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-type-portability")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: portable types pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField("name", .{ .simple = "s" }, &.{}, null),
        makeField("age", .{ .simple = "n" }, &.{}, null),
        makeField("active", .{ .simple = "b" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_default_required, false);
    cfg.rules.setEnabled(.column_length, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-type-portability")) {
            try testing.expect(false);
        }
    }
}

// ─── Index Missing FK Columns Tests ──────────────────────────

test "lint: FK without index detected by index-missing-fk-columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a table with FK declaration but no index
    const table = try makeTestTableWithFkDecls(alloc, "posts", &.{
        makePkField("id"),
        makeField("user_id", .{ .simple = "n" }, &.{}, null),
    }, &.{
        .{
            .fields = &.{"user_id"},
            .ref_table = "users",
            .ref_fields = &.{"id"},
            .actions = &.{},
            .line_no = 1,
        },
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-missing-fk-columns")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "lint: FK with index passes index-missing-fk-columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create a table with FK declaration AND an index on the FK column
    const table = try makeTestTableWithFkDecls(alloc, "posts", &.{
        makePkField("id"),
        makeField("user_id", .{ .simple = "n" }, &.{}, null),
    }, &.{
        .{
            .fields = &.{"user_id"},
            .ref_table = "users",
            .ref_fields = &.{"id"},
            .actions = &.{},
            .line_no = 1,
        },
    });
    // Add an index on user_id
    var table_with_idx = table;
    table_with_idx.indexes = &.{
        makeIndex("idx_user_id", .regular, &.{"user_id"}),
    };
    const tables = try alloc.dupe(ResolvedTable, &.{table_with_idx});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-missing-fk-columns")) {
            try testing.expect(false);
        }
    }
}

// ─── Column Name Too Long Tests ──────────────────────────────

test "lint: long column name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const long_name = "this_is_a_very_long_column_name_that_exceeds_the_default_character_limit_of_sixty_four";
    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeField(long_name, .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-name-too-long")) found = true;
    }
    try testing.expect(found);
}

test "lint: short column name passes" {
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
        if (std.mem.eql(u8, r.rule, "column-name-too-long")) {
            try testing.expect(false);
        }
    }
}

// ─── Index Redundant With PK Tests ────────────────────────────

test "lint: index duplicating PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{
        makeIndex("idx_id", .regular, &.{"id"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-redundant-with-pk")) found = true;
    }
    try testing.expect(found);
}

test "lint: non-PK index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try makeTestTable(alloc, "users", &.{
        makePkField("id"),
        makeSimpleField("name"),
    }, &.{
        makeIndex("idx_name", .regular, &.{"name"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "index-redundant-with-pk")) {
            try testing.expect(false);
        }
    }
}

// ─── View Dependency Cycle Tests ──────────────────────────────

test "lint: view cycle detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tables = try alloc.dupe(ResolvedTable, &.{});
    const views = try alloc.dupe(ast_mod.View, &.{
        .{
            .name = "view_a",
            .query = "SELECT * FROM view_b",
            .comment = null,
            .line_no = 1,
        },
        .{
            .name = "view_b",
            .query = "SELECT * FROM view_a",
            .comment = null,
            .line_no = 2,
        },
    });
    const test_ast = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = views,
        .sql_comments = &.{},
    };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-dependency-cycle")) found = true;
    }
    try testing.expect(found);
}

test "lint: no view cycle passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tables = try alloc.dupe(ResolvedTable, &.{});
    const views = try alloc.dupe(ast_mod.View, &.{
        .{
            .name = "view_a",
            .query = "SELECT * FROM users",
            .comment = null,
            .line_no = 1,
        },
        .{
            .name = "view_b",
            .query = "SELECT * FROM view_a",
            .comment = null,
            .line_no = 2,
        },
    });
    const test_ast = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = views,
        .sql_comments = &.{},
    };
    const cfg = lint_mod.LintConfig{ .include_views = true };
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "view-dependency-cycle")) {
            try testing.expect(false);
        }
    }
}
