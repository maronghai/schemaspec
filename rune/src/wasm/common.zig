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
    // Map error names to numeric codes using comptime-validated rules
    last_error_code = classifyError(err_name);
}

/// Classify an error name into a numeric code.
/// 0 = success, 1 = syntax/parse, 2 = type, 3 = FK, 4 = semantic/diagnostic, 5 = unknown.
fn classifyError(err_name: []const u8) i32 {
    // Check for syntax/parse errors
    if (containsSubstring(err_name, "Syntax") or containsSubstring(err_name, "Parse")) return 1;
    // Check for type errors
    if (containsSubstring(err_name, "Type")) return 2;
    // Check for FK errors
    if (containsSubstring(err_name, "Foreign") or containsSubstring(err_name, "Fk")) return 3;
    // Check for semantic errors
    if (containsSubstring(err_name, "Semantic") or containsSubstring(err_name, "Diagnostic")) return 4;
    // Default: unknown error
    return 5;
}

/// Check if haystack contains needle (case-sensitive substring search).
fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
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
