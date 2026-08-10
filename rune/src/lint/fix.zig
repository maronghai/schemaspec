const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;

// ─── Lint Auto-Fix ──────────────────────────────────────────
// Modifies source text to fix lintable issues.
// Works on raw source text — inserts/removes/modifies lines at the right positions.
//
// Architecture: Each fixable rule has a dedicated handler function.
// The main `fix()` function orchestrates pre-scanning and dispatches
// to per-rule handlers during line-by-line source processing.
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

    if (type_sym.len > 0) {
        const first = type_sym[0];
        if (first == 'n' or first == 'N' or first == 'i' or first == 'I' or first == 'm' or first == 'M' or first == 'e') {
            return " = 0";
        }
        if (first == 'b' and type_sym.len == 1) {
            return " = false";
        }
        if (first == 's' or first == 'S') {
            return " = ''";
        }
        if (first == 't' or first == 'd') {
            return " = CURRENT_TIMESTAMP";
        }
        if (first == 'j') {
            return " = '{}'";
        }
    }

    return null;
}

// ─── Pre-Scan: Build Fix Maps ────────────────────────────────

const FixMaps = struct {
    needs_pk: std.StringHashMap(void),
    needs_timestamps: std.StringHashMap(void),
    needs_empty_removal: std.StringHashMap(void),
    needs_column_default: std.StringHashMap(void),
    needs_fk_index: std.StringHashMap(void),
    needs_column_dedup: std.StringHashMap(void),

    fn deinit(self: *FixMaps) void {
        self.needs_pk.deinit();
        self.needs_timestamps.deinit();
        self.needs_empty_removal.deinit();
        self.needs_column_default.deinit();
        self.needs_fk_index.deinit();
        self.needs_column_dedup.deinit();
    }
};

/// Pre-scan lint results to build per-rule fix maps.
fn buildFixMaps(alloc: std.mem.Allocator, results: []const LintResult) !FixMaps {
    var maps = FixMaps{
        .needs_pk = std.StringHashMap(void).init(alloc),
        .needs_timestamps = std.StringHashMap(void).init(alloc),
        .needs_empty_removal = std.StringHashMap(void).init(alloc),
        .needs_column_default = std.StringHashMap(void).init(alloc),
        .needs_fk_index = std.StringHashMap(void).init(alloc),
        .needs_column_dedup = std.StringHashMap(void).init(alloc),
    };

    for (results) |r| {
        if (LintRule.fromName(r.rule)) |rule| {
            switch (rule) {
                .no_pk => try maps.needs_pk.put(r.table, {}),
                .no_timestamps => try maps.needs_timestamps.put(r.table, {}),
                .empty_table => try maps.needs_empty_removal.put(r.table, {}),
                .column_default_required => try maps.needs_column_default.put(r.table, {}),
                .no_index_fk => try maps.needs_fk_index.put(r.table, {}),
                .duplicate_column => try maps.needs_column_dedup.put(r.table, {}),
                else => {},
            }
        }
    }

    return maps;
}

// ─── Per-Rule Fix Handlers ───────────────────────────────────

/// Fix serial-type: replace "serial"/"bigserial" with "n++" modifier.
/// Returns true if this line was handled (caller should skip normal output).
fn fixSerialType(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
) !bool {
    if (std.mem.indexOf(u8, line, "bigserial")) |pos| {
        if (isWordBoundary(line, pos, 9)) {
            const modified = try replaceWord(alloc, line, pos, 9, "n++");
            defer alloc.free(modified);
            try output.appendSlice(alloc, modified);
            if (line_end < source_len) try output.append(alloc, '\n');
            try fixes.append(alloc, .{
                .rule = "serial-type",
                .table = current_table orelse "",
                .description = "replaced bigserial type with n++ modifier",
            });
            return true;
        }
    } else if (std.mem.indexOf(u8, line, "serial")) |pos| {
        if (isWordBoundary(line, pos, 6)) {
            const modified = try replaceWord(alloc, line, pos, 6, "n++");
            defer alloc.free(modified);
            try output.appendSlice(alloc, modified);
            if (line_end < source_len) try output.append(alloc, '\n');
            try fixes.append(alloc, .{
                .rule = "serial-type",
                .table = current_table orelse "",
                .description = "replaced serial type with n++ modifier",
            });
            return true;
        }
    }
    return false;
}

/// Fix bool-default: add "= false" to boolean fields without defaults.
fn fixBoolDefault(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
    results: []const LintResult,
) !bool {
    if (std.mem.indexOf(u8, line, "=") != null) return false;
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return false;
    const last_char = trimmed[trimmed.len - 1];
    if (last_char != 'b' and !(last_char == '?' and trimmed.len >= 2 and trimmed[trimmed.len - 2] == 'b')) return false;
    if (current_table) |tbl| {
        if (tableNeedsFix(results, tbl, "bool-default")) {
            try output.appendSlice(alloc, line);
            try output.appendSlice(alloc, " = false");
            if (line_end < source_len) try output.append(alloc, '\n');
            try fixes.append(alloc, .{
                .rule = "bool-default",
                .table = tbl,
                .description = "added default value 'false' to boolean column",
            });
            return true;
        }
    }
    return false;
}

/// Fix nullable-column-default: add "= null" to nullable fields without defaults.
fn fixNullableColumnDefault(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
    results: []const LintResult,
) !bool {
    if (std.mem.indexOf(u8, line, "=") != null) return false;
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '?') return false;
    if (current_table) |tbl| {
        if (tableNeedsFix(results, tbl, "nullable-column-default")) {
            try output.appendSlice(alloc, line);
            try output.appendSlice(alloc, " = null");
            if (line_end < source_len) try output.append(alloc, '\n');
            try fixes.append(alloc, .{
                .rule = "nullable-column-default",
                .table = tbl,
                .description = "added default value 'null' to nullable column",
            });
            return true;
        }
    }
    return false;
}

/// Fix column-default-required: add type-appropriate defaults.
fn fixColumnDefaultRequired(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
    needs_column_default: *const std.StringHashMap(void),
) !bool {
    if (std.mem.indexOf(u8, line, "=") != null) return false;
    if (current_table) |tbl| {
        if (needs_column_default.contains(tbl)) {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "index ") and std.mem.indexOf(u8, trimmed, "->") == null) {
                if (detectDefaultValue(trimmed)) |dv| {
                    try output.appendSlice(alloc, line);
                    try output.appendSlice(alloc, dv);
                    if (line_end < source_len) try output.append(alloc, '\n');
                    try fixes.append(alloc, .{
                        .rule = "column-default-required",
                        .table = tbl,
                        .description = "added default value to non-nullable column",
                    });
                    return true;
                }
            }
        }
    }
    return false;
}

/// Fix no-index-fk: add index declaration after FK field lines.
fn fixNoIndexFk(
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

// ─── Main Fix Entry Point ────────────────────────────────────

/// Fix lint issues in the source text. Returns the modified source and a list of fixes applied.
pub fn fix(alloc: std.mem.Allocator, source: []const u8, results: []const LintResult) !struct { source: []u8, fixes: []LintFix } {
    var fixes = try std.ArrayList(LintFix).initCapacity(alloc, results.len);
    errdefer fixes.deinit(alloc);

    var maps = try buildFixMaps(alloc, results);
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
                    if (maps.needs_timestamps.contains(prev_tbl) and !ts_inserted.contains(prev_tbl) and last_field_end > 0) {
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

                if (maps.needs_empty_removal.contains(tbl_name)) {
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
            if (try fixSerialType(alloc, line, &output, line_end, source.len, &fixes, current_table)) continue;
            if (try fixBoolDefault(alloc, line, &output, line_end, source.len, &fixes, current_table, results)) continue;
            if (try fixNullableColumnDefault(alloc, line, &output, line_end, source.len, &fixes, current_table, results)) continue;
            if (try fixColumnDefaultRequired(alloc, line, &output, line_end, source.len, &fixes, current_table, &maps.needs_column_default)) continue;
            if (try fixNoIndexFk(alloc, line, &output, line_end, source.len, &fixes, current_table, &maps.needs_fk_index)) continue;
        }

        // duplicate-index fix: track seen index lines and skip duplicates
        if (in_table and std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "index ")) {
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
                    continue;
                }
                try seen_indexes.put(key, {});
            }
        }

        // duplicate-column fix: track seen column names and skip duplicates
        if (in_table and line.len > 0 and
            line[0] != '#' and line[0] != ';' and line[0] != '@' and line[0] != '$')
        {
            if (current_table) |tbl| {
                if (maps.needs_column_dedup.contains(tbl)) {
                    const trimmed = std.mem.trim(u8, line, " \t");
                    if (trimmed.len > 0) {
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
                            continue;
                        }
                        try seen_columns.put(col_key, {});
                    }
                }
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
