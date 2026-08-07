const std = @import("std");
const LintResult = @import("config.zig").LintResult;

// ─── Lint Auto-Fix ──────────────────────────────────────────
// Modifies source text to fix lintable issues (no-pk, no-timestamps).
// Works on raw source text — inserts lines at the right positions.

pub const LintFix = struct {
    rule: []const u8,
    table: []const u8,
    description: []const u8,
};

/// Fix lint issues in the source text. Returns the modified source and a list of fixes applied.
pub fn fix(alloc: std.mem.Allocator, source: []const u8, results: []const LintResult) !struct { source: []u8, fixes: []LintFix } {
    var fixes = try std.ArrayList(LintFix).initCapacity(alloc, results.len);
    errdefer fixes.deinit(alloc);

    // Pre-scan: find which tables need fixes
    var needs_pk = std.StringHashMap(void).init(alloc);
    defer needs_pk.deinit();
    var needs_timestamps = std.StringHashMap(void).init(alloc);
    defer needs_timestamps.deinit();

    for (results) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) {
            try needs_pk.put(r.table, {});
        } else if (std.mem.eql(u8, r.rule, "no-timestamps")) {
            try needs_timestamps.put(r.table, {});
        }
    }

    // Build output by scanning source character by character
    var output = try std.ArrayList(u8).initCapacity(alloc, source.len + 256);
    errdefer output.deinit(alloc);

    var i: usize = 0;
    var current_table: ?[]const u8 = null;
    var in_table = false;
    var last_field_end: usize = 0;
    var pk_inserted = std.StringHashMap(void).init(alloc);
    defer pk_inserted.deinit();
    var ts_inserted = std.StringHashMap(void).init(alloc);
    defer ts_inserted.deinit();

    while (i < source.len) {
        const line_start = i;
        while (i < source.len and source[i] != '\n') : (i += 1) {}
        const line_end = i;
        if (i < source.len) i += 1;

        const line = source[line_start..line_end];

        // Detect table header
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                // Flush timestamp insertion for previous table
                if (current_table) |prev_tbl| {
                    if (needs_timestamps.contains(prev_tbl) and !ts_inserted.contains(prev_tbl) and last_field_end > 0) {
                        try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t");
                        try fixes.append(alloc, .{
                            .rule = "no-timestamps",
                            .table = prev_tbl,
                            .description = "added created_at and updated_at fields",
                        });
                        try ts_inserted.put(prev_tbl, {});
                    }
                }
                current_table = line[ns..];
                in_table = true;
            }
        }

        // Detect field lines
        if (in_table and line.len > 0 and
            line[0] != '#' and line[0] != ';' and line[0] != '@' and line[0] != '$')
        {
            last_field_end = line_end + 1;
        }

        try output.appendSlice(alloc, line);
        if (line_end < source.len) {
            try output.append(alloc, '\n');
        }

        // After table header line, insert PK if needed
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                const tbl_name = line[ns..];
                if (needs_pk.contains(tbl_name) and !pk_inserted.contains(tbl_name)) {
                    try output.appendSlice(alloc, "id       n++\n");
                    try fixes.append(alloc, .{
                        .rule = "no-pk",
                        .table = tbl_name,
                        .description = "added primary key field 'id'",
                    });
                    try pk_inserted.put(tbl_name, {});
                }
            }
        }
    }

    // Handle timestamps for the last table
    if (current_table) |tbl| {
        if (needs_timestamps.contains(tbl) and !ts_inserted.contains(tbl)) {
            try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t");
            try fixes.append(alloc, .{
                .rule = "no-timestamps",
                .table = tbl,
                .description = "added created_at and updated_at fields",
            });
        }
    }

    return .{ .source = try output.toOwnedSlice(alloc), .fixes = try fixes.toOwnedSlice(alloc) };
}
