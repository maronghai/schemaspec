const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const helpers = @import("fix_helpers.zig");
const LintFix = helpers.LintFix;

// ─── Index & Column Fix Handlers ─────────────────────────────
// Fixes for index and column issues: no-index-fk, duplicate-index, duplicate-column.

/// Fix no-index-fk: add index declaration after FK field lines.
pub fn fixNoIndexFk(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
    needs_fk_index: *const std.StringHashMap(void),
) !bool {
    if (std.mem.indexOf(u8, line, " -> ") == null) return false;
    if (current_table) |tbl| {
        if (needs_fk_index.contains(tbl)) {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                var field_end: usize = 0;
                while (field_end < trimmed.len and trimmed[field_end] != ' ' and trimmed[field_end] != '\t') : (field_end += 1) {}
                const field_name = trimmed[0..field_end];
                try output.appendSlice(alloc, line);
                if (line_end < source_len) try output.append(alloc, '\n');
                try output.appendSlice(alloc, "index idx_");
                try output.appendSlice(alloc, tbl);
                try output.append(alloc, '_');
                try output.appendSlice(alloc, field_name);
                try output.append(alloc, ' ');
                try output.appendSlice(alloc, field_name);
                try output.append(alloc, '\n');
                try fixes.append(alloc, .{
                    .rule = "no-index-fk",
                    .table = tbl,
                    .description = "added index for foreign key column",
                });
                return true;
            }
        }
    }
    return false;
}

/// Fix duplicate-index: track seen index lines and skip duplicates.
/// Returns true if this line should be skipped (duplicate).
pub fn fixDuplicateIndex(
    alloc: std.mem.Allocator,
    line: []const u8,
    current_table: ?[]const u8,
    seen_indexes: *std.StringHashMap(void),
    fixes: *std.ArrayList(LintFix),
) !bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "index ")) return false;
    if (current_table) |tbl| {
        var key_buf = try std.ArrayList(u8).initCapacity(alloc, tbl.len + line.len + 1);
        defer key_buf.deinit(alloc);
        try key_buf.appendSlice(alloc, tbl);
        try key_buf.append(alloc, ':');
        try key_buf.appendSlice(alloc, line);
        const key = try key_buf.toOwnedSlice(alloc);

        if (seen_indexes.contains(key)) {
            try fixes.append(alloc, .{
                .rule = "duplicate-index",
                .table = tbl,
                .description = "removed duplicate index declaration",
            });
            return true;
        }
        try seen_indexes.put(key, {});
    }
    return false;
}

/// Fix duplicate-column: track seen column names and skip duplicates.
/// Returns true if this line should be skipped (duplicate).
pub fn fixDuplicateColumn(
    alloc: std.mem.Allocator,
    line: []const u8,
    current_table: ?[]const u8,
    needs_column_dedup: *const std.StringHashMap(void),
    seen_columns: *std.StringHashMap(void),
    fixes: *std.ArrayList(LintFix),
) !bool {
    if (current_table) |tbl| {
        if (!needs_column_dedup.contains(tbl)) return false;
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) return false;
        var field_end: usize = 0;
        while (field_end < trimmed.len and trimmed[field_end] != ' ' and trimmed[field_end] != '\t') : (field_end += 1) {}
        const field_name = trimmed[0..field_end];

        var col_key_buf = try std.ArrayList(u8).initCapacity(alloc, tbl.len + field_name.len + 1);
        defer col_key_buf.deinit(alloc);
        try col_key_buf.appendSlice(alloc, tbl);
        try col_key_buf.append(alloc, ':');
        try col_key_buf.appendSlice(alloc, field_name);
        const col_key = try col_key_buf.toOwnedSlice(alloc);

        if (seen_columns.contains(col_key)) {
            try fixes.append(alloc, .{
                .rule = "duplicate-column",
                .table = tbl,
                .description = "removed duplicate column declaration",
            });
            return true;
        }
        try seen_columns.put(col_key, {});
    }
    return false;
}
