const std = @import("std");
const protocol = @import("protocol.zig");
const Range = protocol.Range;

/// Convert 1-based line number to 0-based for LSP protocol.
/// Returns 0 if line_no is 0 (undefined).
pub fn lineNoToZeroBased(line_no: anytype) u32 {
    return if (line_no > 0) @intCast(line_no - 1) else 0;
}

pub fn makeRange(start_line: u32, start_char: u32, end_line: u32, end_char: u32) Range {
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };
}

/// Extract the text of a specific line from document content.
/// Returns a slice of the original text (no allocation).
pub fn getLineText(text: []const u8, target_line: u32) []const u8 {
    var line_start: usize = 0;
    var current_line: u32 = 0;
    for (text, 0..) |c, i| {
        if (current_line == target_line) {
            if (c == '\n') return text[line_start..i];
            if (i == text.len - 1) return text[line_start .. i + 1];
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }
    return "";
}

/// Get the actual length of a line (excluding trailing newline).
pub fn lineLength(text: []const u8, target_line: u32) u32 {
    return @intCast(getLineText(text, target_line).len);
}

/// Extract the word under the cursor at the given position.
/// Returns the word if found, null otherwise.
/// Shared by rename.zig's prepareRename and getRenameLinks.
pub fn wordAtPosition(doc_text: []const u8, line: u32, character: u32) ?[]const u8 {
    var line_start: usize = 0;
    var current_line: u32 = 0;
    for (doc_text, 0..) |c, i| {
        if (c == '\n' or i == doc_text.len - 1) {
            if (current_line == line) {
                const line_text = if (c == '\n') doc_text[line_start..i] else doc_text[line_start .. i + 1];
                if (character > line_text.len) return null;
                // Find word boundaries by scanning backwards and forwards from cursor
                var word_end = character;
                while (word_end < line_text.len) : (word_end += 1) {
                    const wc = line_text[word_end];
                    if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                    break;
                }
                var word_start = character;
                while (word_start > 0) : (word_start -= 1) {
                    const wc = line_text[word_start - 1];
                    if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                    break;
                }
                const word = line_text[word_start..word_end];
                if (word.len == 0) return null;
                return word;
            }
            if (c == '\n') {
                line_start = i + 1;
                current_line += 1;
            }
        }
    }
    return null;
}

/// Find the precise character range of `name` on the given 0-indexed line in doc_text.
/// Returns the Range if found as a whole word, null otherwise.
/// Shared by highlights.zig and references.zig to avoid duplication.
pub fn findNameInLine(doc_text: []const u8, target_line: u32, name: []const u8) ?Range {
    // Bound the slice to the target line itself — searching beyond it could
    // match a name on a later line and pin the range to this one.
    const line_text = getLineText(doc_text, target_line);
    if (line_text.len == 0) return null;
    var search_start: usize = 0;
    while (search_start < line_text.len) {
        const pos = std.mem.indexOf(u8, line_text[search_start..], name) orelse break;
        const abs_pos = search_start + pos;
        const before_ok = abs_pos == 0 or !std.ascii.isAlphanumeric(line_text[abs_pos - 1]);
        const after_end = abs_pos + name.len;
        const after_ok = after_end >= line_text.len or !std.ascii.isAlphanumeric(line_text[after_end]);
        if (before_ok and after_ok) {
            return .{
                .start = .{ .line = target_line, .character = @intCast(abs_pos) },
                .end = .{ .line = target_line, .character = @intCast(abs_pos + name.len) },
            };
        }
        search_start = abs_pos + 1;
    }
    return null;
}

/// Format column flags into a human-readable string for hover tooltips.
pub fn formatFlagsForHover(alloc: std.mem.Allocator, flags: anytype) []const u8 {
    var parts = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return "";
    defer parts.deinit(alloc);
    if (flags.primary_key) parts.append(alloc, "PRIMARY KEY") catch {};
    if (flags.auto_increment) parts.append(alloc, "AUTO_INCREMENT") catch {};
    if (flags.nullable) parts.append(alloc, "NULL") catch {};
    if (flags.unsigned) parts.append(alloc, "UNSIGNED") catch {};
    if (flags.inline_unique) parts.append(alloc, "UNIQUE") catch {};
    if (flags.inline_index) parts.append(alloc, "INDEX") catch {};
    if (flags.is_enum) parts.append(alloc, "ENUM") catch {};
    if (flags.is_virtual) parts.append(alloc, "VIRTUAL") catch {};
    if (flags.is_stored) parts.append(alloc, "STORED") catch {};

    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    for (parts.items, 0..) |p, i| {
        if (i > 0) law.writer.writeAll(" ") catch {};
        law.writer.writeAll(p) catch {};
    }
    return law.toOwnedSlice() catch return "";
}
