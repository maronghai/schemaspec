const std = @import("std");

// ─── ANSI Color Codes ──────────────────────────────────────────

pub const RESET = "\x1b[0m";
pub const BOLD = "\x1b[1m";
pub const DIM = "\x1b[2m";

pub const RED = "\x1b[31m";
pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const BLUE = "\x1b[34m";
pub const GRAY = "\x1b[90m";

// ─── Color Mode ────────────────────────────────────────────────

pub const ColorMode = enum {
    auto,
    always,
    never,

    /// Determine if color should be used. For `auto`, checks if stdout is a TTY.
    pub fn shouldUseColor(self: ColorMode, io: std.Io) bool {
        return switch (self) {
            .always => true,
            .never => false,
            .auto => std.Io.File.stdout().isTty(io) catch false,
        };
    }
};

// ─── Helpers ───────────────────────────────────────────────────

/// Write text wrapped in ANSI color codes if color is enabled.
pub fn writeColorized(w: anytype, text: []const u8, color: []const u8, use_color: bool) !void {
    if (use_color) {
        try w.writeAll(color);
        try w.writeAll(text);
        try w.writeAll(RESET);
    } else {
        try w.writeAll(text);
    }
}
