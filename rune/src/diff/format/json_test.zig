const std = @import("std");
const json = @import("json.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "formatDiffJson: produces valid structure" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{"old_table"});
    defer alloc.free(dropped);
    const d = SchemaDiff{
        .dropped_tables = dropped,
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try json.formatDiffJson(alloc, d);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"dropped_tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"table_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"view_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "old_table") != null);
}

test "formatDiffJson: empty diff has empty arrays" {
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"dropped_tables\": []") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"table_diffs\": []") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"view_diffs\": []") != null);
}

test "formatDiffJson: created table with field" {
    const field = diff_types.FieldDiff{
        .name = "email",
        .action = .add,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    };
    const td = diff_types.TableDiff{
        .name = "users",
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
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"action\": \"create\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "email") != null);
}

test "formatDiffJson: field modify shows old and new" {
    const field = diff_types.FieldDiff{
        .name = "status",
        .action = .modify,
        .old_field = .{ .name = "status", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 0 },
        .new_field = .{ .name = "status", .type_info = .{ .simple = "S" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 0 },
        .rename_from = null,
    };
    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{field},
        .index_diffs = &.{},
        .fk_diffs = &.{},
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"action\": \"modify\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "status") != null);
}

test "formatDiffJson: view diff" {
    const vd = diff_types.ViewDiff{
        .name = "active_users",
        .action = .create,
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{},
        .view_diffs = &.{vd},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "active_users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"view_diffs\"") != null);
}

test "formatDiffJson: metadata comment change" {
    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{},
        .index_diffs = &.{},
        .fk_diffs = &.{},
        .metadata_diff = .{
            .old_comment = "old comment",
            .new_comment = "new comment",
            .old_engine = null,
            .new_engine = null,
        },
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"metadata_diff\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"comment\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "old comment") != null);
    try testing.expect(std.mem.indexOf(u8, result, "new comment") != null);
}

test "formatDiffJson: metadata engine change" {
    const td = diff_types.TableDiff{
        .name = "logs",
        .action = .alter,
        .field_diffs = &.{},
        .index_diffs = &.{},
        .fk_diffs = &.{},
        .metadata_diff = .{
            .old_comment = null,
            .new_comment = null,
            .old_engine = "InnoDB",
            .new_engine = "MyISAM",
        },
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"metadata_diff\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"engine\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "InnoDB") != null);
    try testing.expect(std.mem.indexOf(u8, result, "MyISAM") != null);
}

test "formatDiffJson: no metadata when no changes" {
    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{},
        .index_diffs = &.{},
        .fk_diffs = &.{},
        .metadata_diff = .{
            .old_comment = "same",
            .new_comment = "same",
            .old_engine = null,
            .new_engine = null,
        },
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"metadata_diff\"") == null);
}
