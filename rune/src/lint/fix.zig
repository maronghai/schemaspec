const std = @import("std");
const LintResult = @import("config.zig").LintResult;

// ─── Lint Auto-Fix ──────────────────────────────────────────
// Modifies source text to fix lintable issues.
// Works on raw source text — inserts/removes lines at the right positions.
//
// Supported fixable rules:
//   no-pk          — adds "id       n++" after table header
//   no-timestamps  — adds "created_at t\nupdated_at t" before end of table
//   empty-table    — removes empty table blocks (header + blank lines)

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
    var needs_empty_removal = std.StringHashMap(void).init(alloc);
    defer needs_empty_removal.deinit();

    for (results) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) {
            try needs_pk.put(r.table, {});
        } else if (std.mem.eql(u8, r.rule, "no-timestamps")) {
            try needs_timestamps.put(r.table, {});
        } else if (std.mem.eql(u8, r.rule, "empty-table")) {
            try needs_empty_removal.put(r.table, {});
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
    var skipping_empty_table = false;

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

                const tbl_name = line[ns..];
                current_table = tbl_name;
                in_table = true;
                last_field_end = 0;

                // Check if this table needs empty removal
                if (needs_empty_removal.contains(tbl_name)) {
                    skipping_empty_table = true;
                    // Don't output this line — we're removing the entire block
                    continue;
                } else {
                    skipping_empty_table = false;
                }
            }
        }

        // If skipping an empty table, skip all lines until the next table header or EOF
        if (skipping_empty_table) {
            if (line.len > 0 and line[0] == '#') {
                // This is the next table header — stop skipping
                skipping_empty_table = false;
                // Process this line normally (fall through)
            } else {
                // Still inside empty table block — skip this line
                // But record the fix on the first skip
                if (current_table) |tbl| {
                    if (needs_empty_removal.contains(tbl) and !pk_inserted.contains(tbl)) {
                        try fixes.append(alloc, .{
                            .rule = "empty-table",
                            .table = tbl,
                            .description = "removed empty table declaration",
                        });
                        try pk_inserted.put(tbl, {}); // reuse map to track "fix applied"
                    }
                }
                continue;
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

// ─── Tests ─────────────────────────────────────────────────────

const testing = std.testing;

test "fix: no-pk adds primary key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "no-pk", .table = "users", .message = "no pk", .severity = .warning },
    };
    const result = try fix(alloc, "# users\nname s32\n", &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "id       n++") != null);
    try testing.expectEqual(@as(usize, 1), result.fixes.len);
    try testing.expectEqualStrings("no-pk", result.fixes[0].rule);
}

test "fix: no-timestamps adds timestamps" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "no-timestamps", .table = "users", .message = "no ts", .severity = .warning },
    };
    const result = try fix(alloc, "# users\nname s32\n", &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "created_at t") != null);
    try testing.expect(std.mem.indexOf(u8, result.source, "updated_at t") != null);
}

test "fix: empty-table removes empty table block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "empty-table", .table = "empty_tbl", .message = "no fields", .severity = .warning },
    };
    const source = "# empty_tbl\n\n# users\nname s32\n";
    const result = try fix(alloc, source, &results);
    // The empty table block should be removed
    try testing.expect(std.mem.indexOf(u8, result.source, "empty_tbl") == null);
    // The users table should remain
    try testing.expect(std.mem.indexOf(u8, result.source, "# users") != null);
    try testing.expectEqual(@as(usize, 1), result.fixes.len);
    try testing.expectEqualStrings("empty-table", result.fixes[0].rule);
}

test "fix: empty-table at end of file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "empty-table", .table = "users", .message = "no fields", .severity = .warning },
    };
    const source = "# users\nname s32\n\n# empty_tbl\n";
    const result = try fix(alloc, source, &results);
    // The empty table at end should be removed
    try testing.expect(std.mem.indexOf(u8, result.source, "empty_tbl") == null);
    // The users table should remain
    try testing.expect(std.mem.indexOf(u8, result.source, "# users") != null);
}
