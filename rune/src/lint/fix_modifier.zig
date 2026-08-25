const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const helpers = @import("fix_helpers.zig");
const LintFix = helpers.LintFix;

// ─── Modifier Fix Handlers ───────────────────────────────────
// Fixes for field modifiers: serial-type, bool-default, nullable-column-default, column-default-required.

/// True when the line carries an inline comment (`field s32 : note`).
/// Appending a default after the comment would compile the marker text into
/// COMMENT '…' and silently drop the default — such lines are no-fix.
fn hasInlineComment(line: []const u8) bool {
    return std.mem.indexOfScalar(u8, line, ':') != null;
}

/// Fix serial-type: replace "serial"/"bigserial" with "n++" modifier.
/// Returns true if this line was handled (caller should skip normal output).
pub fn fixSerialType(
    alloc: std.mem.Allocator,
    line: []const u8,
    output: *std.ArrayList(u8),
    line_end: usize,
    source_len: usize,
    fixes: *std.ArrayList(LintFix),
    current_table: ?[]const u8,
) !bool {
    if (std.mem.indexOf(u8, line, "bigserial")) |pos| {
        if (helpers.isWordBoundary(line, pos, 9)) {
            const modified = try helpers.replaceWord(alloc, line, pos, 9, "n++");
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
        if (helpers.isWordBoundary(line, pos, 6)) {
            const modified = try helpers.replaceWord(alloc, line, pos, 6, "n++");
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
pub fn fixBoolDefault(
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
    if (hasInlineComment(line)) return false;
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return false;
    const last_char = trimmed[trimmed.len - 1];
    if (last_char != 'b' and !(last_char == '?' and trimmed.len >= 2 and trimmed[trimmed.len - 2] == 'b')) return false;
    if (current_table) |tbl| {
        if (helpers.tableNeedsFix(results, tbl, "bool-default")) {
            // " =false" — one separator space before `=` so the tokenizer
            // yields a standalone "=false" token; no space inside (the
            // default would split into two unknown tokens and be dropped).
            const bare = std.mem.trimEnd(u8, line, " \t\r");
            try output.appendSlice(alloc, bare);
            try output.appendSlice(alloc, " =false");
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
pub fn fixNullableColumnDefault(
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
    if (hasInlineComment(line)) return false;
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '?') return false;
    if (current_table) |tbl| {
        if (helpers.tableNeedsFix(results, tbl, "nullable-column-default")) {
            // " =null" — one separator space before `=` so the tokenizer
            // yields a standalone token; no space inside.
            const bare = std.mem.trimEnd(u8, line, " \t\r");
            try output.appendSlice(alloc, bare);
            try output.appendSlice(alloc, " =null");
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
pub fn fixColumnDefaultRequired(
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
    if (hasInlineComment(line)) return false;
    if (current_table) |tbl| {
        if (needs_column_default.contains(tbl)) {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "index ") and std.mem.indexOf(u8, trimmed, "->") == null) {
                if (helpers.detectDefaultValue(trimmed)) |dv| {
                    // dv carries no internal space by contract ("=0",
                    // "=false", ...); one separator space before `=` keeps it
                    // a single tokenizer token. " = 0" with two spaces would
                    // split into unknown tokens and the default would drop.
                    const bare = std.mem.trimEnd(u8, line, " \t\r");
                    try output.appendSlice(alloc, bare);
                    try output.append(alloc, ' ');
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
