const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;

// ─── Shared Fix Helpers ──────────────────────────────────────
// Common types and helper functions used by all fix handler modules.

pub const LintFix = struct {
    rule: []const u8,
    table: []const u8,
    description: []const u8,
};

/// Check if a word boundary matches at the given position in a line.
pub fn isWordBoundary(line: []const u8, pos: usize, word_len: usize) bool {
    const before_ok = pos == 0 or !std.ascii.isAlphanumeric(line[pos - 1]);
    const after_pos = pos + word_len;
    const after_ok = after_pos >= line.len or !std.ascii.isAlphanumeric(line[after_pos]);
    return before_ok and after_ok;
}

/// Replace a word in a line with a replacement string.
/// Returns the modified line (caller owns the memory).
pub fn replaceWord(alloc: std.mem.Allocator, line: []const u8, pos: usize, word_len: usize, replacement: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, line.len - word_len + replacement.len + 1);
    try result.appendSlice(alloc, line[0..pos]);
    try result.appendSlice(alloc, replacement);
    try result.appendSlice(alloc, line[pos + word_len ..]);
    return try result.toOwnedSlice(alloc);
}

/// Check if a table needs a specific fix rule.
pub fn tableNeedsFix(results: []const LintResult, table: []const u8, rule: []const u8) bool {
    for (results) |r| {
        if (std.mem.eql(u8, r.rule, rule) and std.mem.eql(u8, r.table, table)) {
            return true;
        }
    }
    return false;
}

/// Detect appropriate default value based on type symbol in a field line.
/// Returns the default value string to append (e.g., "=0") or null if
/// unrecognizable. No leading/trailing space: the tokenizer splits on
/// whitespace, so "id n++ = 0" parses as two unknown tokens and the default
/// is silently dropped — the appended text must fuse with the line.
pub fn detectDefaultValue(field_line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, field_line, " \t");
    if (trimmed.len == 0) return null;

    // A datetime field with `+`/`++` already implies DEFAULT
    // CURRENT_TIMESTAMP — appending an explicit one is redundant churn.
    if (isDatetimeWithTimestampDefault(trimmed)) return null;

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
            return "=0";
        }
        if (first == 'b' and type_sym.len == 1) {
            return "=false";
        }
        if (first == 's' or first == 'S') {
            return "=''";
        }
        if (first == 't' or first == 'd') {
            return "=CURRENT_TIMESTAMP";
        }
        if (first == 'j') {
            return "='{}'";
        }
    }

    return null;
}

/// True for a datetime field line (`t`/`d`) whose type symbol carries a
/// trailing `+`/`++` timestamp-default modifier. The modifier scan skips
/// other suffixes so `t?`/`t!` don't match.
fn isDatetimeWithTimestampDefault(line: []const u8) bool {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] != 't' and line[i] != 'd') continue;
        // Must be a standalone symbol: preceded by start/space.
        if (i > 0 and line[i - 1] != ' ' and line[i - 1] != '\t') continue;
        var j = i + 1;
        var saw_plus = false;
        while (j < line.len and line[j] != ' ' and line[j] != '\t') : (j += 1) {
            if (line[j] == '+') {
                saw_plus = true;
            } else if (line[j] != '?' and line[j] != '!') {
                // Another letter — not the bare t/d symbol; bail on this hit.
                break;
            }
        }
        if (j < line.len and line[j] != ' ' and line[j] != '\t') continue;
        if (saw_plus) return true;
    }
    return false;
}

// ─── Pre-Scan: Build Fix Maps ────────────────────────────────

pub const FixMaps = struct {
    needs_pk: std.StringHashMap(void),
    needs_timestamps: std.StringHashMap(void),
    needs_empty_removal: std.StringHashMap(void),
    needs_column_default: std.StringHashMap(void),
    needs_fk_index: std.StringHashMap(void),
    needs_column_dedup: std.StringHashMap(void),

    pub fn deinit(self: *FixMaps) void {
        self.needs_pk.deinit();
        self.needs_timestamps.deinit();
        self.needs_empty_removal.deinit();
        self.needs_column_default.deinit();
        self.needs_fk_index.deinit();
        self.needs_column_dedup.deinit();
    }
};

/// Pre-scan lint results to build per-rule fix maps.
pub fn buildFixMaps(alloc: std.mem.Allocator, results: []const LintResult) !FixMaps {
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

// ─── Tests ─────────────────────────────────────────────────────

const testing = std.testing;

test "detectDefaultValue returns correct defaults" {
    try testing.expectEqualStrings("=0", detectDefaultValue("age n").?);
    try testing.expectEqualStrings("=0", detectDefaultValue("count N").?);
    try testing.expectEqualStrings("=false", detectDefaultValue("is_active b").?);
    try testing.expectEqualStrings("=''", detectDefaultValue("name s100").?);
    try testing.expectEqualStrings("=''", detectDefaultValue("email S").?);
    try testing.expectEqualStrings("=CURRENT_TIMESTAMP", detectDefaultValue("created_at t").?);
    try testing.expectEqualStrings("='{}'", detectDefaultValue("metadata j").?);
    try testing.expectEqualStrings("=0", detectDefaultValue("score e").?);
    try testing.expectEqualStrings("=0", detectDefaultValue("amount m").?);
    try testing.expect(detectDefaultValue("") == null);
}

test "detectDefaultValue skips datetime fields with timestamp-default modifiers" {
    // `+`/`++` on datetime types already imply DEFAULT CURRENT_TIMESTAMP —
    // no fix should append an explicit one.
    try testing.expect(detectDefaultValue("created_at t+") == null);
    try testing.expect(detectDefaultValue("updated_at t++") == null);
    try testing.expect(detectDefaultValue("deleted_at d+") == null);
    // Plain datetime still gets the explicit default.
    try testing.expect(detectDefaultValue("archived_at t") != null);
}
