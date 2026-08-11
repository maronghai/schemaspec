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
