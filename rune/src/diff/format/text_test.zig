const std = @import("std");
const text = @import("text.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "writeDiffTo: empty schema produces no output" {
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try text.writeDiffTo(&aw.writer, d, '`', false);
    try aw.writer.flush();
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "writeDiffTo: dropped table renders DROP TABLE" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{"users"});
    defer alloc.free(dropped);
    const d = SchemaDiff{
        .dropped_tables = dropped,
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    try text.writeDiffTo(&aw.writer, d, '`', false);
    try aw.writer.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "DROP TABLE") != null);
}
