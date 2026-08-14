// FK rule tests — circular-fk, fk-duplicate.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

test "lint: circular FK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table_a = try th.makeTestTableWithFks(alloc, "a", &.{ th.makePkField("id"), th.makeFkFieldTo("b_id", "b", "id") });
    const table_b = try th.makeTestTableWithFks(alloc, "b", &.{ th.makePkField("id"), th.makeFkFieldTo("a_id", "a", "id") });
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_b });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "circular-fk"));
}

test "lint: no circular FK passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table_a = try th.makeTestTableWithFks(alloc, "a", &.{ th.makePkField("id"), th.makeFkFieldTo("b_id", "b", "id") });
    const table_b = try th.makeTestTableWithFks(alloc, "b", &.{ th.makePkField("id"), th.makeFkFieldTo("c_id", "c", "id") });
    const table_c = try th.makeTestTableWithFks(alloc, "c", &.{th.makePkField("id")});
    const tables = try alloc.dupe(ResolvedTable, &.{ table_a, table_b, table_c });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "circular-fk"));
}

test "lint: multiple FKs to same table triggers warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "posts", &.{ th.makePkField("id"), th.makeFkFieldTo("author_id", "users", "id"), th.makeFkFieldTo("reviewer_id", "users", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-duplicate"));
}

test "lint: FKs to different tables passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id"), th.makeFkFieldTo("product_id", "products", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-duplicate"));
}

test "lint: single FK passes fk-duplicate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-duplicate"));
}

test "lint: FK without index triggers fk-missing-index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-missing-index"));
}

test "lint: FK with index passes fk-missing-index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{th.makeIndex("idx_user", .regular, &.{"user_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-missing-index"));
}

test "lint: table without FKs passes fk-missing-index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-missing-index"));
}

// ─── fk-unidirectional tests ──────────────────────────────────

test "lint: table with outgoing FK not referenced triggers fk-unidirectional" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // orders has FK to users, but no table references orders
    const orders = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const users = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{ orders, users });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-unidirectional"));
}

test "lint: mutually referenced tables pass fk-unidirectional" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // orders FKs to users, and users FKs to orders — both are referenced by each other
    const orders = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const users = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeFkFieldTo("primary_order_id", "orders", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{ orders, users });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-unidirectional"));
}

test "lint: table with no FKs passes fk-unidirectional" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{th.makePkField("id")}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-unidirectional"));
}


test "lint: FK to non-unique column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const users = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{});
    const user_email = th.makeField("user_email", .{ .simple = "n" }, &.{}, .{
        .fields = &.{"user_email"},
        .ref_table = "users",
        .ref_fields = &.{"email"},
        .actions = &.{},
        .line_no = 1,
    });
    const orders = try th.makeTestTableWithFks(alloc, "orders", &.{ th.makePkField("id"), user_email });
    const tables = try alloc.dupe(ResolvedTable, &.{ users, orders });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "fk-to-non-unique"));
}

test "lint: FK to primary key column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const users = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id") }, &.{});
    const user_id = th.makeField("user_id", .{ .simple = "n" }, &.{}, .{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    });
    const orders = try th.makeTestTableWithFks(alloc, "orders", &.{ th.makePkField("id"), user_id });
    const tables = try alloc.dupe(ResolvedTable, &.{ users, orders });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-to-non-unique"));
}

test "lint: FK to inline-unique column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const email = th.makeField("email", .{ .simple = "s" }, &.{.{ .kind = .inline_unique, .line_no = 1 }}, null);
    const users = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), email }, &.{});
    const user_email = th.makeField("user_email", .{ .simple = "n" }, &.{}, .{
        .fields = &.{"user_email"},
        .ref_table = "users",
        .ref_fields = &.{"email"},
        .actions = &.{},
        .line_no = 1,
    });
    const orders = try th.makeTestTableWithFks(alloc, "orders", &.{ th.makePkField("id"), user_email });
    const tables = try alloc.dupe(ResolvedTable, &.{ users, orders });
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "fk-to-non-unique"));
}
