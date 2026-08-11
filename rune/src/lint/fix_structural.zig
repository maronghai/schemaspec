const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const helpers = @import("fix_helpers.zig");
const LintFix = helpers.LintFix;

// ─── Structural Fix Handlers ─────────────────────────────────
// Fixes for table structure issues: no primary key, missing timestamps, empty tables.

/// Fix no-pk: insert "id       n++" after table header.
/// Called from the orchestrator when a table header line is detected.
pub fn fixNoPk(
    alloc: std.mem.Allocator,
    output: *std.ArrayList(u8),
    tbl_name: []const u8,
    fixes: *std.ArrayList(LintFix),
    pk_inserted: *std.StringHashMap(void),
) !void {
    try output.appendSlice(alloc, "id       n++\n");
    try fixes.append(alloc, .{
        .rule = "no-pk",
        .table = tbl_name,
        .description = "added primary key field 'id'",
    });
    try pk_inserted.put(tbl_name, {});
}

/// Fix no-timestamps: insert created_at/updated_at at the end of a table.
pub fn fixNoTimestamps(
    alloc: std.mem.Allocator,
    output: *std.ArrayList(u8),
    tbl_name: []const u8,
    fixes: *std.ArrayList(LintFix),
    ts_inserted: *std.StringHashMap(void),
) !void {
    try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t");
    try fixes.append(alloc, .{
        .rule = "no-timestamps",
        .table = tbl_name,
        .description = "added created_at and updated_at fields",
    });
    try ts_inserted.put(tbl_name, {});
}

/// Returns true if this line should be skipped (empty table removal).
pub fn shouldSkipEmptyTable(line: []const u8, tbl_name: []const u8, maps: *const helpers.FixMaps, pk_inserted: *const std.StringHashMap(void), fixes: *std.ArrayList(LintFix), alloc: std.mem.Allocator) !bool {
    if (!maps.needs_empty_removal.contains(tbl_name)) return false;
    if (line.len > 0 and line[0] == '#') return false;
    if (!pk_inserted.contains(tbl_name)) {
        try fixes.append(alloc, .{
            .rule = "empty-table",
            .table = tbl_name,
            .description = "removed empty table declaration",
        });
    }
    return true;
}
