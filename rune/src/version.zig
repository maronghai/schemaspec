const std = @import("std");

/// Rune version constant. Single source of truth for all modules.
pub const VERSION = "0.89.0";

/// Print version to stderr.
pub fn printVersion() void {
    std.debug.print("rune {s}\n", .{VERSION});
}
