const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;
const helpers = @import("fix_helpers.zig");
const structural = @import("fix_structural.zig");
const modifier = @import("fix_modifier.zig");
const index = @import("fix_index.zig");

// ─── Lint Auto-Fix ──────────────────────────────────────────
// Modifies source text to fix lintable issues.
// Works on raw source text — inserts/removes/modifies lines at the right positions.
//
// Architecture: Each fixable rule has a dedicated handler function in a
// category module (fix_structural, fix_modifier, fix_index). Shared helpers
// (LintFix, isWordBoundary, replaceWord, tableNeedsFix, detectDefaultValue,
// buildFixMaps) live in fix_helpers. This file orchestrates the pre-scan
// and dispatches to per-rule handlers during line-by-line source processing.
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
//   duplicate-column           — removes duplicate column declarations
//   index-missing-fk-columns   — adds "index idx_<table>_<field> <field>" for FK columns

pub const LintFix = helpers.LintFix;

// ─── Main Fix Entry Point ────────────────────────────────────

/// Fix lint issues in the source text. Returns the modified source and a list of fixes applied.
pub fn fix(alloc: std.mem.Allocator, source: []const u8, results: []const LintResult) !struct { source: []u8, fixes: []LintFix } {
    var fixes = try std.ArrayList(LintFix).initCapacity(alloc, results.len);
    errdefer fixes.deinit(alloc);

    var maps = try helpers.buildFixMaps(alloc, results);
    defer maps.deinit();

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
    var seen_columns = std.StringHashMap(void).init(alloc);
    defer seen_columns.deinit();
    var fk_col_index_inserted = std.StringHashMap(void).init(alloc);
    defer fk_col_index_inserted.deinit();

    // Pre-scan for index-missing-fk-columns tables
    var needs_fk_col_index = std.StringHashMap(void).init(alloc);
    defer needs_fk_col_index.deinit();
    for (results) |result| {
        if (std.mem.eql(u8, result.rule, "index-missing-fk-columns")) {
            try needs_fk_col_index.put(result.table, {});
        }
    }

    while (i < source.len) {
        const line_start = i;
        while (i < source.len and source[i] != '\n') : (i += 1) {}
        const line_end = i;
        if (i < source.len) i += 1;

        var line = source[line_start..line_end];
        // Handle CRLF line endings: strip trailing CR for matching, remember
        // it, and re-emit it so a no-fix pass is byte-for-byte identical.
        var had_cr = false;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            had_cr = true;
            line = line[0 .. line.len - 1];
        }

        // Detect table header
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                // Flush timestamp insertion for previous table
                if (current_table) |prev_tbl| {
                    if (maps.needs_timestamps.contains(prev_tbl) and !ts_inserted.contains(prev_tbl) and last_field_end > 0) {
                        // Trailing newline required: without it the next table
                        // header fuses into `updated_at t# next` and is parsed
                        // as a field line.
                        try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t\n");
                        try fixes.append(alloc, .{
                            .rule = "no-timestamps",
                            .table = prev_tbl,
                            .description = "added created_at and updated_at fields",
                        });
                        try ts_inserted.put(prev_tbl, {});
                    }
                }

                // Extract table name (stop at comment marker : or end of line)
                var tbl_name_end = line.len;
                var j = ns;
                while (j < line.len) : (j += 1) {
                    if (line[j] == ':') {
                        tbl_name_end = j;
                        break;
                    }
                }
                const tbl_name = line[ns..tbl_name_end];
                // Trim trailing whitespace
                const tbl_name_trimmed = std.mem.trim(u8, tbl_name, " \t");
                current_table = tbl_name_trimmed;
                in_table = true;
                last_field_end = 0;

                if (maps.needs_empty_removal.contains(tbl_name_trimmed)) {
                    skipping_empty_table = true;
                    continue;
                } else {
                    skipping_empty_table = false;
                }
            }
        }

        // If skipping an empty table, skip all lines until the next table header or EOF
        if (skipping_empty_table) {
            if (line.len > 0 and line[0] == '#') {
                skipping_empty_table = false;
            } else {
                if (current_table) |tbl| {
                    if (maps.needs_empty_removal.contains(tbl) and !pk_inserted.contains(tbl)) {
                        try fixes.append(alloc, .{
                            .rule = "empty-table",
                            .table = tbl,
                            .description = "removed empty table declaration",
                        });
                        try pk_inserted.put(tbl, {});
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

            // Dispatch to per-rule fix handlers
            if (try modifier.fixSerialType(alloc, line, &output, line_end, source.len, &fixes, current_table)) continue;
            if (try modifier.fixBoolDefault(alloc, line, &output, line_end, source.len, &fixes, current_table, results)) continue;
            if (try modifier.fixNullableColumnDefault(alloc, line, &output, line_end, source.len, &fixes, current_table, results)) continue;
            if (try modifier.fixColumnDefaultRequired(alloc, line, &output, line_end, source.len, &fixes, current_table, &maps.needs_column_default)) continue;
            if (try index.fixNoIndexFk(alloc, line, &output, line_end, source.len, &fixes, current_table, &maps.needs_fk_index)) continue;
        }

        // duplicate-index fix: track seen index lines and skip duplicates
        if (try index.fixDuplicateIndex(alloc, line, current_table, &seen_indexes, &fixes)) continue;

        // duplicate-column fix: track seen column names and skip duplicates
        if (try index.fixDuplicateColumn(alloc, line, current_table, &maps.needs_column_dedup, &seen_columns, &fixes)) continue;

        // index-missing-fk-columns fix: add index after FK fields in tables that need them
        if (in_table and line.len > 0 and
            line[0] != '#' and line[0] != ';' and line[0] != '@' and line[0] != '$')
        {
            if (current_table) |tbl| {
                if (needs_fk_col_index.contains(tbl) and !fk_col_index_inserted.contains(tbl)) {
                    // Check if this line is an FK field (contains " -> ")
                    if (std.mem.indexOf(u8, line, " -> ") != null) {
                        const trimmed = std.mem.trim(u8, line, " \t");
                        if (trimmed.len > 0) {
                            var field_end: usize = 0;
                            while (field_end < trimmed.len and trimmed[field_end] != ' ' and trimmed[field_end] != '\t') : (field_end += 1) {}
                            const field_name = trimmed[0..field_end];
                            try output.appendSlice(alloc, line);
                            if (line_end < source.len) try output.append(alloc, '\n');
                            try output.appendSlice(alloc, "index idx_");
                            try output.appendSlice(alloc, tbl);
                            try output.append(alloc, '_');
                            try output.appendSlice(alloc, field_name);
                            try output.append(alloc, ' ');
                            try output.appendSlice(alloc, field_name);
                            try output.append(alloc, '\n');
                            try fixes.append(alloc, .{
                                .rule = "index-missing-fk-columns",
                                .table = tbl,
                                .description = "added index for FK column",
                            });
                            try fk_col_index_inserted.put(tbl, {});
                            continue;
                        }
                    }
                }
            }
        }

        try output.appendSlice(alloc, line);
        if (had_cr) try output.append(alloc, '\r');
        if (line_end < source.len) {
            try output.append(alloc, '\n');
        }

        // After table header line, insert PK if needed
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                // Extract table name (stop at comment marker : or end of line)
                var tbl_name_end = line.len;
                var j = ns;
                while (j < line.len) : (j += 1) {
                    if (line[j] == ':') {
                        tbl_name_end = j;
                        break;
                    }
                }
                const tbl_name = std.mem.trim(u8, line[ns..tbl_name_end], " \t");
                if (maps.needs_pk.contains(tbl_name) and !pk_inserted.contains(tbl_name)) {
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
        if (maps.needs_timestamps.contains(tbl) and !ts_inserted.contains(tbl)) {
            try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t\n");
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
    try testing.expect(std.mem.indexOf(u8, result.source, "empty_tbl") == null);
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
    try testing.expect(std.mem.indexOf(u8, result.source, "empty_tbl") == null);
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
    const first_pos = std.mem.indexOf(u8, result.source, "index idx_name name").?;
    const second_pos = std.mem.indexOf(u8, result.source[first_pos + 1 ..], "index idx_name name");
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
    // "=0" (no internal space) is the parseable form — "= 0" splits into
    // two unknown tokens and the default silently drops.
    try testing.expect(std.mem.indexOf(u8, result.source, " =0") != null);
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
    try testing.expect(std.mem.indexOf(u8, result.source, " =''") != null);
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
    try testing.expect(std.mem.indexOf(u8, result.source, " =false") != null);
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

test "fix: duplicate-column removes second occurrence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "duplicate-column", .table = "users", .message = "dup col", .severity = .warning },
    };
    const source = "# users\nname s32\nage n\nname s64\n";
    const result = try fix(alloc, source, &results);
    const first_pos = std.mem.indexOf(u8, result.source, "name s32").?;
    const rest = result.source[first_pos + 8 ..];
    try testing.expect(std.mem.indexOf(u8, rest, "name") == null);
    try testing.expect(result.fixes.len > 0);
    try testing.expectEqualStrings("duplicate-column", result.fixes[0].rule);
}

test "fix: detectDefaultValue returns correct defaults" {
    try testing.expectEqualStrings("=0", helpers.detectDefaultValue("age n").?);
    try testing.expectEqualStrings("=0", helpers.detectDefaultValue("count N").?);
    try testing.expectEqualStrings("=false", helpers.detectDefaultValue("is_active b").?);
    try testing.expectEqualStrings("=''", helpers.detectDefaultValue("name s100").?);
    try testing.expectEqualStrings("=''", helpers.detectDefaultValue("email S").?);
    try testing.expectEqualStrings("=CURRENT_TIMESTAMP", helpers.detectDefaultValue("created_at t").?);
    try testing.expectEqualStrings("='{}'", helpers.detectDefaultValue("metadata j").?);
    try testing.expectEqualStrings("=0", helpers.detectDefaultValue("score e").?);
    try testing.expectEqualStrings("=0", helpers.detectDefaultValue("amount m").?);
    try testing.expect(helpers.detectDefaultValue("") == null);
}

test "fix: index-missing-fk-columns adds index for FK column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const results = [_]LintResult{
        .{ .rule = "index-missing-fk-columns", .table = "posts", .message = "FK column user_id has no index", .severity = .warning },
    };
    const source = "# posts\nid n ++\nuser_id n -> users.id\n";
    const result = try fix(alloc, source, &results);
    try testing.expect(std.mem.indexOf(u8, result.source, "index idx_posts_user_id user_id") != null);
    try testing.expect(result.fixes.len > 0);
    try testing.expectEqualStrings("index-missing-fk-columns", result.fixes[0].rule);
}
