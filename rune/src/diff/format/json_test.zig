const std = @import("std");
const json = @import("json.zig");
const diff_types = @import("../types.zig");
const SchemaDiff = diff_types.SchemaDiff;

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "formatDiffJson: produces valid structure" {
    const d = SchemaDiff{
        .dropped_tables = &.{"old_table"},
        .view_diffs = &.{},
        .table_diffs = &.{},
    };
    const result = try json.formatDiffJson(testing.allocator, d);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"dropped_tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"table_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"view_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "old_table") != null);
}
