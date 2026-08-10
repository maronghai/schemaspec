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
//   column-default-required    — adds "= 0" for numeric, "= ''" for string, "= false" for boolean
//   no-index-fk                — adds "index idx_<table>_<field> <field>" after FK field

pub const LintFix = struct {
    rule: []const u8,
    table: []const u8,
    description: []const u8,
};

// ─── Helper Functions ────────────────────────────────────────

/// Check if a word boundary matches at the given position in a line.
fn isWordBoundary(line: []const u8, pos: usize, word_len: usize) bool {
    const before_ok = pos == 0 or !std.ascii.isAlphanumeric(line[pos - 1]);
    const after_pos = pos + word_len;
    const after_ok = after_pos >= line.len or !std.ascii.isAlphanumeric(line[after_pos]);
    return before_ok and after_ok;
}

/// Replace a word in a line with a replacement string.
/// Returns the modified line (caller owns the memory).
fn replaceWord(alloc: std.mem.Allocator, line: []const u8, pos: usize, word_len: usize, replacement: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, line.len - word_len + replacement.len + 1);
    try result.appendSlice(alloc, line[0..pos]);
    try result.appendSlice(alloc, replacement);
    try result.appendSlice(alloc, line[pos + word_len ..]);
    return try result.toOwnedSlice(alloc);
}

/// Check if a table needs a specific fix rule.
fn tableNeedsFix(results: []const LintResult, table: []const u8, rule: []const u8) bool {
    for (results) |r| {
        if (std.mem.eql(u8, r.rule, rule) and std.mem.eql(u8, r.table, table)) {
            return true;
        }
    }
    return false;
}

/// Detect appropriate default value based on type symbol in a field line.
/// Returns the default value string to append (e.g., " = 0") or null if unrecognizable.
fn detectDefaultValue(field_line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, field_line, " \t");
    if (trimmed.len == 0) return null;

    // Find the type symbol — it's typically the last non-modifier token
    // Patterns: "name s32", "name n", "name b", "name t", "name s100?"
    var last_token_start: usize = trimmed.len;
    var pos = trimmed.len;
    // Skip trailing modifiers (?, !, u, @)
    while (pos > 0 and (trimmed[pos - 1] == '?' or trimmed[pos - 1] == '!' or trimmed[pos - 1] == 'u' or trimmed[pos - 1] == '@')) {
        pos -= 1;
    }
    // Find start of last token
    last_token_start = pos;
    while (last_token_start > 0 and trimmed[last_token_start - 1] != ' ' and trimmed[last_token_start - 1] != '\t') {
        last_token_start -= 1;
    }
    const type_sym = trimmed[last_token_start..pos];

    // Numeric types: n, N, i, I, m, M, e, and suffixed variants
    if (type_sym.len > 0) {
        const first = type_sym[0];
        if (first == 'n' or first == 'N' or first == 'i' or first == 'I' or first == 'm' or first == 'M' or first == 'e') {
            return " = 0";
        }
        // Boolean type: b
        if (first == 'b' and type_sym.len == 1) {
            return " = false";
        }
        // String types: s, S (including s32, s100, etc.)
        if (first == 's' or first == 'S') {
            return " = ''";
        }
        // Datetime types: t, d, dt
        if (first == 't' or first == 'd') {
            return " = CURRENT_TIMESTAMP";
        }
        // JSON type: j
        if (first == 'j') {
            return " = '{}'";
        }
    }

    return null;
}

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
    var needs_column_default = std.StringHashMap(void).init(alloc);
    defer needs_column_default.deinit();
    var needs_fk_index = std.StringHashMap(void).init(alloc);
    defer needs_fk_index.deinit();

    for (results) |r| {
        if (LintRule.fromName(r.rule)) |rule| {
            switch (rule) {
                .no_pk => try needs_pk.put(r.table, {}),
                .no_timestamps => try needs_timestamps.put(r.table, {}),
                .empty_table => try needs_empty_removal.put(r.table, {}),
                .column_default_required => try needs_column_default.put(r.table, {}),
                .no_index_fk => try needs_fk_index.put(r.table, {}),
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
                if (isWordBoundary(line, pos, 9)) { // 9 = len("bigserial")
                    const modified = try replaceWord(alloc, line, pos, 9, "n++");
                    defer alloc.free(modified);
                    try output.appendSlice(alloc, modified);
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
                if (isWordBoundary(line, pos, 6)) { // 6 = len("serial")
                    const modified = try replaceWord(alloc, line, pos, 6, "n++");
                    defer alloc.free(modified);
                    try output.appendSlice(alloc, modified);
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
                            if (tableNeedsFix(results, tbl, "bool-default")) {
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
                        if (tableNeedsFix(results, tbl, "nullable-column-default")) {
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

            // column-default-required fix: add "= 0" for numeric, "= ''" for string, "= false" for boolean
            // Heuristic: line has no "=" sign and is a type field (not index, not FK)
            if (line.len >= 1 and std.mem.indexOf(u8, line, "=") == null) {
                if (current_table) |tbl| {
                    if (needs_column_default.contains(tbl)) {
                        const trimmed3 = std.mem.trim(u8, line, " \t");
                        // Skip lines that are already index or FK declarations
                        if (trimmed3.len > 0 and !std.mem.startsWith(u8, trimmed3, "index ") and std.mem.indexOf(u8, trimmed3, "->") == null) {
                            // Detect type symbol to choose appropriate default
                            const default_val = detectDefaultValue(trimmed3);
                            if (default_val) |dv| {
                                try output.appendSlice(alloc, line);
                                try output.appendSlice(alloc, dv);
                                if (line_end < source.len) {
                                    try output.append(alloc, '\n');
                                }
                                try fixes.append(alloc, .{
                                    .rule = "column-default-required",
                                    .table = tbl,
                                    .description = "added default value to non-nullable column",
                                });
                                continue;
                            }
                        }
                    }
                }
            }

            // no-index-fk fix: add index declaration after FK field lines
            // Heuristic: line contains " -> " (FK declaration)
            if (std.mem.indexOf(u8, line, " -> ") != null) {
                if (current_table) |tbl| {
                    if (needs_fk_index.contains(tbl)) {
                        // Extract field name (first word before spaces)
                        const trimmed4 = std.mem.trim(u8, line, " \t");
                        if (trimmed4.len > 0) {
                            var field_end: usize = 0;
                            while (field_end < trimmed4.len and trimmed4[field_end] != ' ' and trimmed4[field_end] != '\t') : (field_end += 1) {}
                            const field_name = trimmed4[0..field_end];

                            // Output the original line first
                            try output.appendSlice(alloc, line);
                            if (line_end < source.len) {
                                try output.append(alloc, '\n');
                            }
                            // Then insert the index declaration
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
                            continue;
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

test "fix: column-default-required adds numeric default" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "column-default-required", .table = "users", .message = "no default", .severity = .info },
    };
    const source = "# users\nid n ++\nage n\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "= 0") != null);
    try testing.expect(result.fixes.len > 0);
}

test "fix: column-default-required adds string default" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "column-default-required", .table = "users", .message = "no default", .severity = .info },
    };
    const source = "# users\nid n ++\nname s100\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "= ''") != null);
}

test "fix: column-default-required adds boolean default" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "column-default-required", .table = "users", .message = "no default", .severity = .info },
    };
    const source = "# users\nid n ++\nis_active b\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "= false") != null);
}

test "fix: no-index-fk adds index after FK field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "no-index-fk", .table = "posts", .message = "no index", .severity = .warning },
    };
    const source = "# posts\nid n ++\nuser_id n -> users.id\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "index idx_posts_user_id user_id") != null);
    try testing.expect(result.fixes.len > 0);
}

test "fix: detectDefaultValue returns correct defaults" {
    try testing.expectEqualStrings(" = 0", detectDefaultValue("age n").?);
    try testing.expectEqualStrings(" = 0", detectDefaultValue("count N").?);
    try testing.expectEqualStrings(" = false", detectDefaultValue("is_active b").?);
    try testing.expectEqualStrings(" = ''", detectDefaultValue("name s100").?);
    try testing.expectEqualStrings(" = ''", detectDefaultValue("email S").?);
    try testing.expectEqualStrings(" = CURRENT_TIMESTAMP", detectDefaultValue("created_at t").?);
    try testing.expectEqualStrings(" = '{}'", detectDefaultValue("metadata j").?);
    try testing.expectEqualStrings(" = 0", detectDefaultValue("score e").?);
    try testing.expectEqualStrings(" = 0", detectDefaultValue("amount m").?);
    try testing.expect(detectDefaultValue("") == null);
}
