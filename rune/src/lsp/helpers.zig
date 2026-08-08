const std = @import("std");
const protocol = @import("protocol.zig");
const Range = protocol.Range;

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
