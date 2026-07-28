const std = @import("std");
const common = @import("common.zig");
const dialect = @import("dialect.zig");

// ─── Tests ───────────────────────────────────────────────────

const testing = std.testing;

test "quoteIdentDoubleQuote: basic" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try common.quoteIdentDoubleQuote(w, "users");
    try w.flush();
    const out = try aw.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("\"users\"", out);
}

test "emitIndex: unique" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    const w = &aw.writer;
    var needs_comma = false;
    try common.emitIndex(w, .{ .kind = .unique, .name = "uk_email", .fields = &.{"email"}, .descending = &.{}, .line_no = 0 }, &needs_comma);
    try w.flush();
    const out = try aw.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"email\"") != null);
}

test "emitIndex: regular is no-op" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    const w = &aw.writer;
    var needs_comma = false;
    try common.emitIndex(w, .{ .kind = .regular, .name = "idx_foo", .fields = &.{"col"}, .descending = &.{}, .line_no = 0 }, &needs_comma);
    try w.flush();
    const out = try aw.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expectEqual(@as(usize, 0), out.len);
}

test "emitAlterDropColumn: double-quoted" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try common.emitAlterDropColumn(w, "age");
    try w.flush();
    const out = try aw.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("DROP COLUMN \"age\"", out);
}

test "emitAlterRenameColumn: double-quoted" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try common.emitAlterRenameColumn(w, "old_name", "new_name");
    try w.flush();
    const out = try aw.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("RENAME COLUMN \"old_name\" TO \"new_name\"", out);
}
