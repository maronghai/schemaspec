const std = @import("std");
const columns = @import("columns.zig");
const dialect = @import("../dialect/dialect.zig");

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

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
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

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "UNSIGNED") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"count\"") != null);
}
