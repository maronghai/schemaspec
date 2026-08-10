const std = @import("std");
const build_options = @import("build_options");

/// Rune version constant. Single source of truth for all modules.
/// Injected from build.zig.zon at compile time via build_options.
pub const VERSION = build_options.VERSION;

/// Print version to stderr.
pub fn printVersion() void {
    std.debug.print("rune {s}\n", .{VERSION});
}

/// Print version as JSON to stderr.
pub fn printVersionJson() void {
    std.debug.print("{{\"version\":\"{s}\",\"binary\":\"rune\"}}\n", .{VERSION});
}
