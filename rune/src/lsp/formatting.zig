const std = @import("std");
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── Document Formatting ───────────────────────────────────

/// Format the entire document using the Rune formatter.
pub fn getFormatting(alloc: std.mem.Allocator, text: []const u8) ?[]const u8 {
    return getFormattingDialect(alloc, text, null);
}

/// Format with dialect-specific SQL keyword handling.
pub fn getFormattingDialect(alloc: std.mem.Allocator, text: []const u8, dialect: ?Dialect) ?[]const u8 {
    const formatter = @import("../formatter.zig");
    return formatter.formatDialect(alloc, text, dialect) catch |err| {
        std.log.err("formatting failed: {s}", .{@errorName(err)});
        return null;
    };
}
