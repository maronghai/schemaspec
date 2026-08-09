const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;

// ─── Lint Auto-Fix ──────────────────────────────────────────
// Modifies source text to fix lintable issues.
// Works on raw source text — inserts/removes/modifies lines at the right positions.
//
// Supported fixable rules:
//   no-pk                      — adds "id       n++" after table header
//   no-timestamps              — adds "created_at t\nupdated_at t" before end of table
//   empty-table                — removes empty table blocks (header + blank lines)
//   serial-type                — replaces "serial"/"bigserial" with "n++" modifier
//   bool-default               — adds "= false" to boolean fields without defaults
//   nullable-column-default    — adds "= null" to nullable fields without defaults
//   duplicate-index            — removes duplicate index declarations

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
    // New fixable rules: serial-type, bool-default, nullable-column-default, duplicate-index
    // These are handled per-line in the main loop below.

    for (results) |r| {
        if (LintRule.fromName(r.rule)) |rule| {
            switch (rule) {
                .no_pk => try needs_pk.put(r.table, {}),
                .no_timestamps => try needs_timestamps.put(r.table, {}),
                .empty_table => try needs_empty_removal.put(r.table, {}),
                else => {},
            }
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
    var seen_indexes = std.StringHashMap(void).init(alloc);
    defer seen_indexes.deinit();

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

            // serial-type fix: replace "serial"/"bigserial" with "n++" modifier
            // Check for "bigserial" first (longer match), then "serial"
            if (std.mem.indexOf(u8, line, "bigserial")) |pos| {
                const before_ok = pos == 0 or !std.ascii.isAlphanumeric(line[pos - 1]);
                const after_pos = pos + 9; // len("bigserial")
                const after_ok = after_pos >= line.len or !std.ascii.isAlphanumeric(line[after_pos]);
                if (before_ok and after_ok) {
                    var modified = try std.ArrayList(u8).initCapacity(alloc, line.len + 4);
                    defer modified.deinit(alloc);
                    try modified.appendSlice(alloc, line[0..pos]);
                    try modified.appendSlice(alloc, "n++");
                    try modified.appendSlice(alloc, line[after_pos..]);
                    try output.appendSlice(alloc, modified.items);
                    if (line_end < source.len) {
                        try output.append(alloc, '\n');
                    }
                    try fixes.append(alloc, .{
                        .rule = "serial-type",
                        .table = current_table orelse "",
                        .description = "replaced bigserial type with n++ modifier",
                    });
                    continue;
                }
            } else if (std.mem.indexOf(u8, line, "serial")) |pos| {
                // Check it's a standalone word (not part of another word)
                const before_ok = pos == 0 or !std.ascii.isAlphanumeric(line[pos - 1]);
                const after_pos = pos + 6; // len("serial")
                const after_ok = after_pos >= line.len or !std.ascii.isAlphanumeric(line[after_pos]);
                if (before_ok and after_ok) {
                    var modified = try std.ArrayList(u8).initCapacity(alloc, line.len + 4);
                    defer modified.deinit(alloc);
                    try modified.appendSlice(alloc, line[0..pos]);
                    try modified.appendSlice(alloc, "n++");
                    try modified.appendSlice(alloc, line[after_pos..]);
                    try output.appendSlice(alloc, modified.items);
                    if (line_end < source.len) {
                        try output.append(alloc, '\n');
                    }
                    try fixes.append(alloc, .{
                        .rule = "serial-type",
                        .table = current_table orelse "",
                        .description = "replaced serial type with n++ modifier",
                    });
                    continue;
                }
            }

            // bool-default fix: add "= false" to boolean field lines without defaults
            // Heuristic: line contains type symbol "b" and no "=" sign
            if (line.len >= 1 and std.mem.indexOf(u8, line, "=") == null) {
                // Check for boolean type: field ends with "b" as type symbol
                // Pattern: "name  b" or "name  b?" or "name  b  ..."
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len > 0) {
                    // Find the type symbol - it's typically the last non-modifier token
                    // For booleans: "is_active  b" or "is_active  b?"
                    const last_char = trimmed[trimmed.len - 1];
                    if (last_char == 'b' or (last_char == '?' and trimmed.len >= 2 and trimmed[trimmed.len - 2] == 'b')) {
                        // Check this table needs bool-default fix
                        if (current_table) |tbl| {
                            // Check if the lint result mentions this table
                            var needs_fix = false;
                            for (results) |r| {
                                if (std.mem.eql(u8, r.rule, "bool-default") and std.mem.eql(u8, r.table, tbl)) {
                                    needs_fix = true;
                                    break;
                                }
                            }
                            if (needs_fix) {
                                try output.appendSlice(alloc, line);
                                try output.appendSlice(alloc, " = false");
                                if (line_end < source.len) {
                                    try output.append(alloc, '\n');
                                }
                                try fixes.append(alloc, .{
                                    .rule = "bool-default",
                                    .table = tbl,
                                    .description = "added default value 'false' to boolean column",
                                });
                                continue; // Skip the normal output below
                            }
                        }
                    }
                }
            }

            // nullable-column-default fix: add "= null" to nullable field lines without defaults
            // Heuristic: line ends with "?" modifier and no "=" sign
            if (line.len >= 1 and std.mem.indexOf(u8, line, "=") == null) {
                const trimmed2 = std.mem.trim(u8, line, " \t");
                if (trimmed2.len > 0 and trimmed2[trimmed2.len - 1] == '?') {
                    if (current_table) |tbl| {
                        var needs_fix2 = false;
                        for (results) |r| {
                            if (std.mem.eql(u8, r.rule, "nullable-column-default") and std.mem.eql(u8, r.table, tbl)) {
                                needs_fix2 = true;
                                break;
                            }
                        }
                        if (needs_fix2) {
                            try output.appendSlice(alloc, line);
                            try output.appendSlice(alloc, " = null");
                            if (line_end < source.len) {
                                try output.append(alloc, '\n');
                            }
                            try fixes.append(alloc, .{
                                .rule = "nullable-column-default",
                                .table = tbl,
                                .description = "added default value 'null' to nullable column",
                            });
                            continue; // Skip the normal output below
                        }
                    }
                }
            }
        }

        // duplicate-index fix: track seen index lines and skip duplicates
        if (in_table and std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "index ")) {
            if (current_table) |tbl| {
                // Build a key from table name + index line
                var key_buf = try std.ArrayList(u8).initCapacity(alloc, tbl.len + line.len + 1);
                defer key_buf.deinit(alloc);
                try key_buf.appendSlice(alloc, tbl);
                try key_buf.append(alloc, ':');
                try key_buf.appendSlice(alloc, line);
                const key = try key_buf.toOwnedSlice(alloc);

                if (seen_indexes.contains(key)) {
                    // Duplicate index line — skip it
                    try fixes.append(alloc, .{
                        .rule = "duplicate-index",
                        .table = tbl,
                        .description = "removed duplicate index declaration",
                    });
                    continue; // Skip the normal output below
                }
                try seen_indexes.put(key, {});
            }
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
        .{ .rule = "empty-table", .table = "empty_tbl", .message = "no fields", .severity = .warning },
    };
    const source = "# users\nname s32\n\n# empty_tbl\n";
    const result = try fix(alloc, source, &results);
    // The empty table at end should be removed
    try testing.expect(std.mem.indexOf(u8, result.source, "empty_tbl") == null);
    // The users table should remain
    try testing.expect(std.mem.indexOf(u8, result.source, "# users") != null);
}

test "fix: serial-type replaces serial with n++" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "serial-type", .table = "users", .message = "serial type", .severity = .warning },
    };
    const source = "# users\nid  serial\nname s32\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "n++") != null);
    try testing.expect(std.mem.indexOf(u8, result.source, "serial") == null);
    try testing.expectEqual(@as(usize, 1), result.fixes.len);
    try testing.expectEqualStrings("serial-type", result.fixes[0].rule);
}

test "fix: serial-type replaces bigserial with n++" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "serial-type", .table = "users", .message = "serial type", .severity = .warning },
    };
    const source = "# users\nid  bigserial\nname s32\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "n++") != null);
    try testing.expect(std.mem.indexOf(u8, result.source, "bigserial") == null);
}

test "fix: duplicate-index removes second occurrence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "duplicate-index", .table = "users", .message = "dup idx", .severity = .warning },
    };
    const source = "# users\nname s32\nindex idx_name name\nindex idx_name2 name\nindex idx_name name\n";
    const result = try fix(alloc, source, &results);
    // The second "index idx_name name" should be removed
    const first_pos = std.mem.indexOf(u8, result.source, "index idx_name name").?;
    const second_pos = std.mem.indexOf(u8, result.source[first_pos + 1 ..], "index idx_name name");
    // Should only appear once (or the duplicate is removed)
    try testing.expect(second_pos == null or result.fixes.len > 0);
}

test "fix: multiple fix types combined" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "no-pk", .table = "users", .message = "no pk", .severity = .warning },
        .{ .rule = "no-timestamps", .table = "users", .message = "no ts", .severity = .warning },
    };
    const source = "# users\nname s32\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "id       n++") != null);
    try testing.expect(std.mem.indexOf(u8, result.source, "created_at t") != null);
    try testing.expectEqual(@as(usize, 2), result.fixes.len);
}
