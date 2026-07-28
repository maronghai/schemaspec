const std = @import("std");
const sarif = @import("sarif.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "formatDiffSarif: produces valid SARIF structure" {
    const alloc = testing.allocator;
    const dropped = try alloc.dupe([]const u8, &.{"old_table"});
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
