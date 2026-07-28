const std = @import("std");
const sarif = @import("sarif.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "formatDiffSarif: produces valid SARIF structure" {
    const d = SchemaDiff{
        .dropped_tables = &.{"old_table"},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(testing.allocator, d, .mysql);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\": \"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"ruleId\": \"schema/dropped-table\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "old_table") != null);
}

test "formatDiffSarif: empty diff produces valid structure" {
    const d = SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try sarif.formatDiffSarif(testing.allocator, d, .mysql);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\": \"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"results\": [") != null);
}
