// Validation rule tests — fk-cascade, nullable-pk, fk-null, fk-depth, unique-constraint,
// composite-pk, column-default-required, nullable-column-default, bool-default,
// column-auto-increment-type, column-unique-naming, column-auto-increment-nullable.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ast_mod = @import("../types/ast.zig");
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

test "lint: FK without cascade actions detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkField("user_id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-cascade"));
}

test "lint: FK with both cascade actions passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const actions = [_]ast_mod.FkAction{ .{ .trigger = .on_delete, .action = .cascade }, .{ .trigger = .on_update, .action = .cascade } };
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldWithActions("user_id", &actions) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-cascade"));
}

test "lint: FK with only ON DELETE detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const actions = [_]ast_mod.FkAction{.{ .trigger = .on_delete, .action = .cascade }};
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldWithActions("user_id", &actions) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRuleWithSubstring(results, "fk-cascade", "ON UPDATE"));
}

test "lint: nullable PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } }, null), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "nullable-pk"));
}

test "lint: non-nullable PK passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "nullable-pk"));
}

test "lint: nullable FK column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fk_field = ast_mod.Field{ .name = "user_id", .type_info = .{ .simple = "n" }, .modifiers = &.{.{ .kind = .nullable, .line_no = 1 }}, .default_val = null, .check = null, .fk = .{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 }, .comment = null, .line_no = 1 };
    const fk_decl = ast_mod.FkDecl{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 };
    const table = try th.makeTestTableWithFkDecls(alloc, "orders", &.{ th.makePkField("id"), fk_field }, &.{fk_decl});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-null"));
}

test "lint: non-nullable FK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fk_field = ast_mod.Field{ .name = "user_id", .type_info = .{ .simple = "n" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = .{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 }, .comment = null, .line_no = 1 };
    const fk_decl = ast_mod.FkDecl{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 };
    const table = try th.makeTestTableWithFkDecls(alloc, "orders", &.{ th.makePkField("id"), fk_field }, &.{fk_decl});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-null"));
}

test "lint: FK chain depth 1 passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table_a = try th.makeTestTableWithFks(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") });
    const table_users = try th.makeTestTableWithFks(alloc, "users", &.{th.makePkField("id")});
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_users });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-depth"));
}

test "lint: FK chain depth 4 triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const l4 = try th.makeTestTableWithFks(alloc, "level4", &.{ th.makePkField("id"), th.makeFkFieldTo("level3_id", "level3", "id") });
    const l3 = try th.makeTestTableWithFks(alloc, "level3", &.{ th.makePkField("id"), th.makeFkFieldTo("level2_id", "level2", "id") });
    const l2 = try th.makeTestTableWithFks(alloc, "level2", &.{ th.makePkField("id"), th.makeFkFieldTo("level1_id", "level1", "id") });
    const l1 = try th.makeTestTableWithFks(alloc, "level1", &.{ th.makePkField("id"), th.makeFkFieldTo("base_id", "base", "id") });
    const base = try th.makeTestTableWithFks(alloc, "base", &.{th.makePkField("id")});
    const tables = try alloc.dupe(ResolvedTable, &.{ l4, l3, l2, l1, base });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-depth"));
}

test "lint: UNIQUE on PK column triggers redundancy warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("uniq_id", .unique, &.{"id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "unique-constraint"));
}

test "lint: UNIQUE on non-PK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{th.makeIndex("uniq_email", .unique, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "unique-constraint"));
}

test "lint: multiple auto-inc PKs triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "bad_table", &.{ th.makeField("id1", .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null), th.makeField("id2", .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "composite-pk"));
}

test "lint: single auto-inc PK passes composite-pk check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "composite-pk"));
}

test "lint: non-PK non-nullable column without default triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-default-required"));
}

test "lint: nullable column passes column-default-required" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-default-required"));
}

test "lint: boolean without default detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("active", .{ .simple = "b" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "bool-default"));
}

test "lint: boolean with default passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("active", .{ .simple = "b" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.bool_default, false);
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), cfg);
    try testing.expect(!th.findRule(results, "bool-default"));
}

test "lint: nullable column without default triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "nullable-column-default"));
}

test "lint: nullable column with default passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("bio", .{ .simple = "s" }, &.{.{ .kind = .nullable, .line_no = 1 }}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.nullable_column_default, false);
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), cfg);
    try testing.expect(!th.findRule(results, "nullable-column-default"));
}

test "lint: nullable unique column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tables = try alloc.dupe(ResolvedTable, &.{try th.makeTestTable(alloc, "users", &.{th.makeField("email", .{ .varchar_explicit = 128 }, &.{ .{ .kind = .inline_unique, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } }, null)}, &.{})});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-unique-nullable"));
}

test "lint: non-nullable unique column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tables = try alloc.dupe(ResolvedTable, &.{try th.makeTestTable(alloc, "users", &.{th.makeField("email", .{ .varchar_explicit = 128 }, &.{.{ .kind = .inline_unique, .line_no = 1 }}, null)}, &.{})});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-unique-nullable"));
}

test "lint: FK type mismatch detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const users_table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const posts_table = try th.makeTestTableWithFkDecls(alloc, "posts", &.{th.makeField("user_id", .{ .varchar_explicit = 32 }, &.{}, null)}, &.{.{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 2 }});
    const tables = try alloc.dupe(ResolvedTable, &.{ users_table, posts_table });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-column-type-mismatch"));
}

test "lint: FK type match passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const users_table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const posts_table = try th.makeTestTableWithFkDecls(alloc, "posts", &.{th.makeField("user_id", .{ .simple = "n" }, &.{}, null)}, &.{.{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 2 }});
    const tables = try alloc.dupe(ResolvedTable, &.{ users_table, posts_table });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-column-type-mismatch"));
}

// ─── column-auto-increment-type tests ─────────────────────────

test "lint: auto-increment on string type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makeField("id", .{ .simple = "s" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-auto-increment-type"));
}

test "lint: auto-increment on integer type passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-auto-increment-type"));
}

test "lint: auto-increment on boolean type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "flags", &.{
        th.makeField("id", .{ .simple = "b" }, &.{.{ .kind = .auto_inc, .line_no = 1 }}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-auto-increment-type"));
}

// ─── column-unique-naming tests ───────────────────────────────

test "lint: case-insensitive duplicate column names detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
        th.makeField("Name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-unique-naming"));
}

test "lint: distinct column names pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makeField("first_name", .{ .simple = "s" }, &.{}, null),
        th.makeField("last_name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-unique-naming"));
}

// ─── fk-on-delete-cascade tests ───────────────────────────────

test "lint: FK ON DELETE CASCADE detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const actions = [_]ast_mod.FkAction{.{ .trigger = .on_delete, .action = .cascade }};
    const table = try th.makeTestTable(alloc, "posts", &.{th.makeFkFieldWithActions("user_id", &actions)}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-on-delete-cascade"));
}

test "lint: FK ON DELETE RESTRICT passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const actions = [_]ast_mod.FkAction{.{ .trigger = .on_delete, .action = .restrict }};
    const table = try th.makeTestTable(alloc, "posts", &.{th.makeFkFieldWithActions("user_id", &actions)}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-on-delete-cascade"));
}

test "lint: FK ON DELETE SET NULL passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const actions = [_]ast_mod.FkAction{.{ .trigger = .on_delete, .action = .set_null }};
    const table = try th.makeTestTable(alloc, "posts", &.{th.makeFkFieldWithActions("user_id", &actions)}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-on-delete-cascade"));
}

// ─── column-auto-increment-nullable tests ──────────────────────

test "lint: auto-increment on nullable column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .auto_inc_pk, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } }, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-auto-increment-nullable"));
}

test "lint: auto-increment on non-nullable column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-auto-increment-nullable"));
}

test "lint: auto_inc (non-pk) on nullable column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "counters", &.{
        th.makeField("seq", .{ .simple = "n" }, &.{ .{ .kind = .auto_inc, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } }, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-auto-increment-nullable"));
}
