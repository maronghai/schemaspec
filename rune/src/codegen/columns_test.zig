const std = @import("std");
const columns = @import("columns.zig");
const dialect = @import("../dialect/dialect.zig");
const ast_mod = @import("../types/ast.zig");

// ─── Unit Tests ─────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../semantic/test_helpers.zig");
const makeTestColumn = test_helpers.makeTestColumn;

test "emitColumnDef: MySQL table" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("balance", .{ .decimal = .{ .precision = 16, .scale = 2 } });
    col.flags.nullable = false;
    col.flags.unsigned = true;
    col.default = "0";

    const backend = dialect.getBackend(.mysql);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "`balance`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "decimal(16, 2)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "UNSIGNED") != null);
    try testing.expect(std.mem.indexOf(u8, result, "NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, result, "DEFAULT 0") != null);
}

test "emitColumnDef: PG omits UNSIGNED" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("count", .int);
    col.flags.unsigned = true;

    const backend = dialect.getBackend(.pg);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "UNSIGNED") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"count\"") != null);
}

test "emitDefault: numeric value without quotes" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try columns.emitDefault(w, "42");
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings(" DEFAULT 42", result);
}

test "emitDefault: float value without quotes" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try columns.emitDefault(w, "3.14");
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings(" DEFAULT 3.14", result);
}

test "emitDefault: string value with quotes" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try columns.emitDefault(w, "hello");
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings(" DEFAULT 'hello'", result);
}

test "emitDefault: CURRENT_TIMESTAMP without quotes" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try columns.emitDefault(w, "CURRENT_TIMESTAMP");
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings(" DEFAULT CURRENT_TIMESTAMP", result);
}

test "emitDefault: NULL without quotes" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try columns.emitDefault(w, "NULL");
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings(" DEFAULT NULL", result);
}

test "emitColumnDef: nullable column omits NOT NULL" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("email", .{ .varchar = 255 });
    col.flags.nullable = true;

    const backend = dialect.getBackend(.mysql);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "NOT NULL") == null);
}

test "emitColumnDef: auto_increment renders for MySQL" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("id", .int);
    col.flags.auto_increment = true;
    col.flags.primary_key = true;

    const backend = dialect.getBackend(.mysql);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "AUTO_INCREMENT") != null);
    try testing.expect(std.mem.indexOf(u8, result, "PRIMARY KEY") != null);
}

test "emitColumnDef: comment renders for MySQL" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("name", .{ .varchar = 100 });
    col.comment = "user name";

    const backend = dialect.getBackend(.mysql);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "COMMENT 'user name'") != null);
}

test "emitColumnDef: SQLite renders without UNSIGNED" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    var col = makeTestColumn("amount", .{ .decimal = .{ .precision = 10, .scale = 2 } });
    col.flags.unsigned = true;

    const backend = dialect.getBackend(.sqlite);
    try columns.emitColumnDef(backend, w, col);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "UNSIGNED") == null);
    try testing.expect(std.mem.indexOf(u8, result, "`amount`") != null);
}

test "emitCheckExpr: range constraint" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    const ck = ast_mod.CheckConstraint{ .kind = .range, .expr = "1, 100", .line_no = 1 };
    try columns.emitCheckExpr(w, "age", ck);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings("age BETWEEN 1 AND 100", result);
}

test "emitCheckExpr: in_list constraint" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    const ck = ast_mod.CheckConstraint{ .kind = .in_list, .expr = "'active', 'inactive'", .line_no = 1 };
    try columns.emitCheckExpr(w, "status", ck);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "status IN (") != null);
    try testing.expect(std.mem.indexOf(u8, result, "'active'") != null);
}

test "emitCheckExpr: comparison >= constraint" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    const ck = ast_mod.CheckConstraint{ .kind = .comparison, .expr = ">=18", .line_no = 1 };
    try columns.emitCheckExpr(w, "age", ck);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings("age >= 18", result);
}

test "emitCheckExpr: comparison < constraint" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    const ck = ast_mod.CheckConstraint{ .kind = .comparison, .expr = "<150", .line_no = 1 };
    try columns.emitCheckExpr(w, "age", ck);
    try w.flush();

    const result = try aw.toOwnedSlice();
    defer alloc.free(result);

    try testing.expectEqualStrings("age < 150", result);
}
