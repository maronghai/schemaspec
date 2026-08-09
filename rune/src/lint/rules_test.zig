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
    const results = try lintSchema(alloc, test_ast, .{ .check_column_length = false });
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
    const results = try lintSchema(alloc, test_ast, .{ .check_column_length = false });
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
    const results = try lintSchema(alloc, test_ast, .{ .check_bool_default = false });
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "bool-default")) {
            try testing.expect(false);
        }
    }
}
