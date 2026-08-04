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

test "writeDiffTo: multiple dropped tables" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{ "users", "posts" });
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
    try testing.expect(std.mem.indexOf(u8, result, "users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "posts") != null);
}

test "writeDiffTo: created table renders CREATE TABLE" {
    const field = diff_types.FieldDiff{
        .name = "email",
        .action = .add,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    };
    const td = diff_types.TableDiff{
        .name = "contacts",
        .action = .create,
        .field_diffs = &.{field},
        .index_diffs = &.{},
        .fk_diffs = &.{},
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try text.writeDiffTo(&aw.writer, d, '`', false);
    try aw.writer.flush();
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "CREATE TABLE") != null);
    try testing.expect(std.mem.indexOf(u8, result, "contacts") != null);
}

test "writeDiffTo: altered table with field add and drop" {
    const alloc = testing.allocator;
    const add_field = diff_types.FieldDiff{
        .name = "phone",
        .action = .add,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    };
    const drop_field = diff_types.FieldDiff{
        .name = "fax",
        .action = .drop,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    };
    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{ add_field, drop_field },
        .index_diffs = &.{},
        .fk_diffs = &.{},
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    try text.writeDiffTo(&aw.writer, d, '`', false);
    try aw.writer.flush();
    const result = try aw.toOwnedSlice();
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "phone (add)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "fax (drop)") != null);
}
