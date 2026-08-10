const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const enums = @import("../types/enums.zig");

// ─── WASM Shared State ──────────────────────────────────────────
// Global state shared across all WASM export modules.

/// Global arena allocator for WASM. Grows across calls; reset with rune_reset().
pub var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);

/// Last error message from rune_compile. Null when no error has occurred.
pub var last_error: ?[*:0]const u8 = null;

/// Numeric error code from the last operation. 0 = success.
/// 1 = syntax error, 2 = type error, 3 = FK error, 4 = semantic error, 5 = unknown error.
pub var last_error_code: i32 = 0;

/// Clear previous error state.
pub fn clearError() void {
    last_error = null;
    last_error_code = 0;
}

/// Store an error message for retrieval via rune_last_error().
pub fn storeError(alloc: std.mem.Allocator, err_name: []const u8) void {
    last_error = alloc.dupeZ(u8, err_name) catch null;
    // Map error names to numeric codes
    last_error_code = if (std.mem.indexOf(u8, err_name, "Syntax") != null or std.mem.indexOf(u8, err_name, "Parse") != null)
        1
    else if (std.mem.indexOf(u8, err_name, "Type") != null)
        2
    else if (std.mem.indexOf(u8, err_name, "Foreign") != null or std.mem.indexOf(u8, err_name, "Fk") != null)
        3
    else if (std.mem.indexOf(u8, err_name, "Semantic") != null or std.mem.indexOf(u8, err_name, "Diagnostic") != null)
        4
    else
        5;
}

/// Parse "key=value" from a space-separated options string.
pub fn parseOption(options: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, options, ' ');
    while (iter.next()) |token| {
        if (std.mem.indexOfScalar(u8, token, '=')) |eq| {
            if (std.mem.eql(u8, token[0..eq], key)) {
                return token[eq + 1 ..];
            }
        }
    }
    return null;
}

/// Parse dialect from WASM options string. Returns .mysql as default.
pub fn parseDialectOption(options: []const u8) dialect_enum.Dialect {
    if (parseOption(options, "dialect")) |val| {
        return dialect_enum.parseDialect(val) catch .mysql;
    }
    return .mysql;
}

/// Parse diff format from WASM options string. Returns .text as default.
pub fn parseDiffFormatOption(options: []const u8) enums.DiffFormat {
    if (parseOption(options, "format")) |val| {
        return std.meta.stringToEnum(enums.DiffFormat, val) orelse .text;
    }
    return .text;
}
