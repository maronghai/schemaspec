const std = @import("std");

// ─── Standardized Error Formatting ────────────────────────────
// Consistent error message format across all modules.
// Format: "error[rule]: message" or "warning[rule]: message"

pub const ErrorFormatter = struct {
    /// Format a standard error message.
    /// Returns: "error[{rule}]: {message}"
    pub fn formatError(rule: []const u8, message: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "error[{s}]: {s}", .{ rule, message });
    }

    /// Format a standard warning message.
    /// Returns: "warning[{rule}]: {message}"
    pub fn formatWarning(rule: []const u8, message: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "warning[{s}]: {s}", .{ rule, message });
    }

    /// Format an error with context.
    /// Returns: "error[{rule}]: {message} in {context}"
    pub fn formatErrorWithContext(rule: []const u8, message: []const u8, context: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "error[{s}]: {s} in {s}", .{ rule, message, context });
    }

    /// Format a warning with context.
    /// Returns: "warning[{rule}]: {message} in {context}"
    pub fn formatWarningWithContext(rule: []const u8, message: []const u8, context: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "warning[{s}]: {s} in {s}", .{ rule, message, context });
    }
};

// ─── Convenience Functions ────────────────────────────────────

/// Print a standardized error to stderr.
pub fn printError(rule: []const u8, message: []const u8) void {
    std.debug.print("error[{s}]: {s}\n", .{ rule, message });
}

/// Print a standardized warning to stderr.
pub fn printWarning(rule: []const u8, message: []const u8) void {
    std.debug.print("warning[{s}]: {s}\n", .{ rule, message });
}

/// Print a standardized error with context to stderr.
pub fn printErrorWithContext(rule: []const u8, message: []const u8, context: []const u8) void {
    std.debug.print("error[{s}]: {s} in {s}\n", .{ rule, message, context });
}

/// Print a standardized warning with context to stderr.
pub fn printWarningWithContext(rule: []const u8, message: []const u8, context: []const u8) void {
    std.debug.print("warning[{s}]: {s} in {s}\n", .{ rule, message, context });
}

// ─── Tests ────────────────────────────────────────────────────

test "ErrorFormatter.formatError" {
    const result = try ErrorFormatter.formatError("E001", "file not found");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("error[E001]: file not found", result);
}

test "ErrorFormatter.formatWarning" {
    const result = try ErrorFormatter.formatWarning("W001", "unused variable");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("warning[W001]: unused variable", result);
}

test "ErrorFormatter.formatErrorWithContext" {
    const result = try ErrorFormatter.formatErrorWithContext("E002", "parse error", "input.ss");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("error[E002]: parse error in input.ss", result);
}

test "ErrorFormatter.formatWarningWithContext" {
    const result = try ErrorFormatter.formatWarningWithContext("W002", "deprecated syntax", "schema.ss");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("warning[W002]: deprecated syntax in schema.ss", result);
}
