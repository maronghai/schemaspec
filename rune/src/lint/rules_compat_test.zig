// Compatibility rule tests — serial-type, cross-dialect-types, column-type-portability, reserved-word.

const std = @import("std");
const testing = std.testing;
const th = @import("test_helpers.zig");
const lint_mod = @import("../lint.zig");
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

test "lint: serial type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makeField("id", .{ .simple = "serial" }, &.{}, null), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "serial-type"));
}

test "lint: bigserial type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "events", &.{ th.makeField("id", .{ .simple = "bigserial" }, &.{}, null), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "serial-type"));
}

test "lint: non-serial type passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "serial-type"));
}

test "lint: MySQL UNSIGNED type triggers cross-dialect warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("amount", .{ .simple = "unsigned" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "cross-dialect-types"));
}

test "lint: TINYINT type triggers cross-dialect info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "flags", &.{ th.makePkField("id"), th.makeField("flag", .{ .simple = "tinyint" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "cross-dialect-types"));
}

test "lint: cross-portable type passes cross-dialect check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    cfg.rules.setEnabled(.column_length, false);
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), cfg);
    try testing.expect(!th.findRule(results, "cross-dialect-types"));
}

test "lint: reserved word table name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "select", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "reserved-word"));
}

test "lint: reserved word column name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("order", .{ .simple = "n" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRuleWithSubstring(results, "reserved-word", "column name"));
}

test "lint: non-reserved word passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "reserved-word"));
}

test "lint: MySQL-specific tinyint detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("age", .{ .simple = "tinyint" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-type-portability"));
}

test "lint: portable types pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeField("name", .{ .simple = "s" }, &.{}, null), th.makeField("age", .{ .simple = "n" }, &.{}, null), th.makeField("active", .{ .simple = "b" }, &.{}, null) }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_default_required, false);
    cfg.rules.setEnabled(.column_length, false);
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), cfg);
    try testing.expect(!th.findRule(results, "column-type-portability"));
}

test "lint: unsigned-overflow-risk positive (unsigned + auto-increment numeric)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const id = th.makeField("id", .{ .simple = "N" }, &.{ .{ .kind = .unsigned, .line_no = 1 }, .{ .kind = .auto_inc, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "widgets", &.{id}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "unsigned-overflow-risk"));
}

test "lint: unsigned-overflow-risk negative (unsigned but not auto-increment)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const col = th.makeField("balance", .{ .simple = "N" }, &.{ .{ .kind = .unsigned, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "accounts", &.{ th.makePkField("id"), col }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "unsigned-overflow-risk"));
}

test "lint: unsigned-overflow-risk negative (auto-increment but not unsigned)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const id = th.makeField("id", .{ .simple = "N" }, &.{ .{ .kind = .auto_inc, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "widgets", &.{id}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "unsigned-overflow-risk"));
}

test "lint: unsigned-overflow-risk negative (unsigned + auto-increment but non-numeric)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const col = th.makeField("flag", .{ .simple = "b" }, &.{ .{ .kind = .unsigned, .line_no = 1 }, .{ .kind = .auto_inc, .line_no = 1 } }, null);
    const table = try th.makeTestTable(alloc, "widgets", &.{ th.makePkField("id"), col }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "unsigned-overflow-risk"));
}


test "lint: charset-collation-portability positive (mysql-specific utf8mb4)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var ast = th.makeAst(tables);
    ast.schema_charset = "utf8mb4";
    const results = try lint_mod.lintSchema(alloc, ast, .{});
    try testing.expect(th.findRule(results, "charset-collation-portability"));
}

test "lint: charset-collation-portability positive (collation-style value)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var ast = th.makeAst(tables);
    ast.schema_charset = "utf8mb4_0900_ai_ci";
    const results = try lint_mod.lintSchema(alloc, ast, .{});
    try testing.expect(th.findRule(results, "charset-collation-portability"));
}

test "lint: charset-collation-portability positive (latin1)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var ast = th.makeAst(tables);
    ast.schema_charset = "latin1";
    const results = try lint_mod.lintSchema(alloc, ast, .{});
    try testing.expect(th.findRule(results, "charset-collation-portability"));
}

test "lint: charset-collation-portability negative (neutral utf8 passes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    var ast = th.makeAst(tables);
    ast.schema_charset = "utf8";
    const results = try lint_mod.lintSchema(alloc, ast, .{});
    try testing.expect(!th.findRule(results, "charset-collation-portability"));
}

test "lint: charset-collation-portability negative (no charset)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{ th.makePkField("id"), th.makeSimpleField("name") }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "charset-collation-portability"));
}


test "lint: decimal-precision-portability fires when precision exceeds portable bound (Db2 cap 31)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "ledger", &.{
        th.makePkField("id"),
        th.makeField("amount", .{ .decimal_explicit = .{ .precision = 40, .scale = 2 } }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "decimal-precision-portability"));
}

test "lint: decimal-precision-portability fires when scale exceeds precision (malformed)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "ledger", &.{
        th.makePkField("id"),
        th.makeField("ratio", .{ .decimal_explicit = .{ .precision = 10, .scale = 20 } }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "decimal-precision-portability"));
}

test "lint: decimal-precision-portability quiet for portable precision (<= 31)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "ledger", &.{
        th.makePkField("id"),
        th.makeField("amount", .{ .decimal_explicit = .{ .precision = 20, .scale = 2 } }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "decimal-precision-portability"));
}

test "lint: decimal-precision-portability quiet for non-decimal columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .simple = "varchar" }, &.{}, null),
        th.makeField("count", .{ .simple = "n" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lint_mod.lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(!th.findRule(results, "decimal-precision-portability"));
}
