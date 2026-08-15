// Index rule tests — no-index-fk, unused-index, duplicate-index, index-column-missing,
// index-missing-fk-columns, column-name-too-long, index-redundant-with-pk, table-no-index.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

test "lint: FK without index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "no-index-fk"));
}

test "lint: FK with index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{th.makeIndex("idx_user_id", .regular, &.{"user_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "no-index-fk"));
}

test "lint: unused index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-unused"));
}

test "lint: FK-covered index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{th.makeIndex("idx_user_id", .regular, &.{"user_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-unused"));
}

test "lint: unique index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{th.makeIndex("idx_email", .unique, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-unused"));
}

test "lint: duplicate index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{ th.makeIndex("idx_name", .regular, &.{"name"}), th.makeIndex("idx_name_2", .regular, &.{"name"}) });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "duplicate-index"));
}

test "lint: no duplicate index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name"), th.makeSimpleField("email") }, &.{ th.makeIndex("idx_name", .regular, &.{"name"}), th.makeIndex("idx_email", .regular, &.{"email"}) });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "duplicate-index"));
}

test "lint: different index kinds are not duplicates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{ th.makeIndex("idx_name", .regular, &.{"name"}), th.makeIndex("uniq_name", .unique, &.{"name"}) });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "duplicate-index"));
}

test "lint: index referencing non-existent column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_bad", .regular, &.{"nonexistent_col"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-column-missing"));
}

test "lint: index referencing valid column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-column-missing"));
}

test "lint: composite index with missing column detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_composite", .regular, &.{ "name", "missing_col" })});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-column-missing"));
}

test "lint: FK without index detected by index-missing-fk-columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTableWithFkDecls(alloc, "posts", &.{ th.makePkField("id"), th.makeField("user_id", .{ .simple = "n" }, &.{}, null) }, &.{.{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 }});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-missing-fk-columns"));
}

test "lint: FK with index passes index-missing-fk-columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var table = try th.makeTestTableWithFkDecls(alloc, "posts", &.{ th.makePkField("id"), th.makeField("user_id", .{ .simple = "n" }, &.{}, null) }, &.{.{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 1 }});
    table.indexes = &.{th.makeIndex("idx_user_id", .regular, &.{"user_id"})};
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-missing-fk-columns"));
}

test "lint: long column name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const long_name = "this_is_a_very_long_column_name_that_exceeds_the_default_character_limit_of_sixty_four";
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField(long_name, .{ .simple = "s" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-name-too-long"));
}

test "lint: short column name passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "column-name-too-long"));
}

test "lint: index duplicating PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_id", .regular, &.{"id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-redundant-with-pk"));
}

test "lint: non-PK index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-redundant-with-pk"));
}

// ─── table-no-index tests ─────────────────────────────────────

test "lint: table with no indexes detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "table-no-index"));
}

test "lint: table with indexes passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "table-no-index"));
}

test "lint: empty table skips table-no-index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "empty", &.{}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "table-no-index"));
}


// ─── index-name-too-long tests ──────────────────────────────

test "lint: oversized index name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // column_name_max defaults to 64
    const long_name = "idx_this_is_an_unreasonably_long_index_name_that_exceeds_the_default_limit_of_sixty_four_characters";
    try testing.expect(long_name.len > 64);
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{th.makeIndex(long_name, .regular, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-name-too-long"));
}

test "lint: normal index name passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{th.makeIndex("idx_email", .regular, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-name-too-long"));
}


// ─── index-redundant-with-fk tests ──────────────────────────

test "lint: index duplicating FK auto-index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{th.makeIndex("idx_user_id", .regular, &.{"user_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-redundant-with-fk"));
}

test "lint: index on non-FK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id"), th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-redundant-with-fk"));
}

test "lint: unique index on FK column passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{th.makeIndex("idx_user_id", .unique, &.{"user_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-redundant-with-fk"));
}

test "lint: FK without standalone index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "orders", &.{ th.makePkField("id"), th.makeFkFieldTo("user_id", "users", "id") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-redundant-with-fk"));
}

// ─── index-redundant-with-unique tests ──────────────────────

test "lint: regular index on UNIQUE column detected as redundant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const email = th.makeField("email", .{ .varchar_explicit = 128 }, &.{ .{ .kind = .inline_unique, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), email }, &.{th.makeIndex("idx_email", .regular, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-redundant-with-unique"));
    // Must not also fire the PK/FK variants for an ordinary unique column.
    try testing.expect(!th.findRule(results, "index-redundant-with-pk"));
    try testing.expect(!th.findRule(results, "index-redundant-with-fk"));
}

test "lint: regular index on non-UNIQUE column is not redundant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const email = th.makeField("email", .{ .varchar_explicit = 128 }, &.{}, null);
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), email }, &.{th.makeIndex("idx_email", .regular, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-redundant-with-unique"));
}

test "lint: regular index duplicating a unique index detected as redundant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("email") }, &.{
        th.makeIndex("uniq_email", .unique, &.{"email"}),
        th.makeIndex("idx_email", .regular, &.{"email"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-redundant-with-unique"));
    // duplicate-index compares type+columns; the two indexes differ in type, so it stays quiet.
    try testing.expect(!th.findRule(results, "duplicate-index"));
}


// ─── index-consistency-pass tests ──────────────────────────

test "lint: index-consistency-pass — unique index duplicating inline unique column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const email = th.makeField("email", .{ .varchar_explicit = 128 }, &.{ .{ .kind = .inline_unique, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), email }, &.{th.makeIndex("uniq_email", .unique, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-consistency-pass"));
    // duplicate-index compares same-kind indexes; a unique index vs an inline-unique
    // modifier is different "kind", so it stays quiet.
    try testing.expect(!th.findRule(results, "duplicate-index"));
    // index-redundant-with-unique only fires on regular indexes.
    try testing.expect(!th.findRule(results, "index-redundant-with-unique"));
}

test "lint: index-consistency-pass — unique index on non-unique column is quiet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{th.makeIndex("uniq_name", .unique, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-consistency-pass"));
}

test "lint: index-consistency-pass — regular index prefix of composite PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const a = th.makeField("tenant_id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const b = th.makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "rows", &.{ a, b, th.makeSimpleField("name") }, &.{th.makeIndex("idx_tenant", .regular, &.{"tenant_id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-consistency-pass"));
    // The prefix is shorter than the PK, so index-redundant-with-pk must not also fire.
    try testing.expect(!th.findRule(results, "index-redundant-with-pk"));
}

test "lint: index-consistency-pass — regular index prefix of unique index detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "members", &.{ th.makePkField("id"), th.makeSimpleField("tenant_id"), th.makeSimpleField("user_id") }, &.{
        th.makeIndex("uniq_tenant_user", .unique, &.{"tenant_id", "user_id"}),
        th.makeIndex("idx_tenant", .regular, &.{"tenant_id"}),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "index-consistency-pass"));
    // index-redundant-with-unique only fires on exact (set-equal) matches.
    try testing.expect(!th.findRule(results, "index-redundant-with-unique"));
    try testing.expect(!th.findRule(results, "duplicate-index"));
}

test "lint: index-consistency-pass — regular index not a prefix is quiet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const a = th.makeField("tenant_id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const b = th.makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "rows", &.{ a, b, th.makeSimpleField("name") }, &.{th.makeIndex("idx_name", .regular, &.{"name"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "index-consistency-pass"));
}

test "lint: index-consistency-pass — exact PK duplicate handled by sibling, not here" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const a = th.makeField("tenant_id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const b = th.makeField("id", .{ .simple = "n" }, &.{ .{ .kind = .primary_key, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "rows", &.{ a, b }, &.{th.makeIndex("idx_pk", .regular, &.{"tenant_id", "id"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    // Exact match belongs to index-redundant-with-pk, not the prefix rule.
    try testing.expect(th.findRule(results, "index-redundant-with-pk"));
    try testing.expect(!th.findRule(results, "index-consistency-pass"));
}

test "lint: index-consistency-pass — regular index on inline-unique column is not a prefix duplicate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const email = th.makeField("email", .{ .varchar_explicit = 128 }, &.{ .{ .kind = .inline_unique, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), email }, &.{th.makeIndex("idx_email", .regular, &.{"email"})});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    // Exact match is index-redundant-with-unique territory.
    try testing.expect(th.findRule(results, "index-redundant-with-unique"));
    try testing.expect(!th.findRule(results, "index-consistency-pass"));
}
