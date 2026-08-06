const std = @import("std");
const sarif = @import("sarif.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "formatDiffSarif: produces valid SARIF structure" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{"old_table"});
    defer alloc.free(dropped);
    const d = SchemaDiff{
        .dropped_tables = dropped,
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\": \"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\": \"schema/dropped-table\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "old_table") != null);
}

test "formatDiffSarif: empty diff produces valid structure" {
    const alloc = testing.allocator;
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\": \"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"results\": [") != null);
}

test "formatDiffSarif: field add produces result" {
    const alloc = testing.allocator;
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
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "users") != null);
}

test "formatDiffSarif: multiple dropped tables" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{ "users", "posts" });
    defer alloc.free(dropped);
    const d = SchemaDiff{
        .dropped_tables = dropped,
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "posts") != null);
    // Each dropped table should produce a separate result
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\": \"schema/dropped-table\"") != null);
}

test "formatDiffSarif: view diff produces result" {
    const alloc = testing.allocator;
    const vd = diff_types.ViewDiff{
        .name = "active_users",
        .action = .create,
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{},
        .view_diffs = &.{vd},
    };
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\": \"schema/view-create\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "active_users") != null);
}

test "formatDiffSarif: metadata comment change produces result" {
    const alloc = testing.allocator;
    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{},
        .index_diffs = &.{},
        .fk_diffs = &.{},
        .metadata_diff = .{
            .old_comment = "old",
            .new_comment = "new",
            .old_engine = null,
            .new_engine = null,
        },
    };
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\": \"schema/metadata-comment\"") != null);
}

test "formatDiffSarif: no metadata result when no changes" {
    const alloc = testing.allocator;
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
    const result = try sarif.formatDiffSarif(alloc, d, .mysql);
    defer alloc.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "metadata") == null);
}
