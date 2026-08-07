const std = @import("std");

// ─── Document Formatting ───────────────────────────────────

/// Format the entire document using the Rune formatter.
pub fn getFormatting(alloc: std.mem.Allocator, text: []const u8) ?[]const u8 {
    const formatter = @import("../formatter.zig");
    return formatter.format(alloc, text) catch null;
}
