const std = @import("std");

// ─── Standardized Error Formatting ────────────────────────────
// Consistent error message format across all modules.
// Format: "error[rule]: message" or "warning[rule]: message"

pub const ErrorFormatter = struct {
    /// Format a standard error message.
    /// Returns: "error[{rule}]: {message}"
    pub fn formatError(alloc: std.mem.Allocator, rule: []const u8, message: []const u8) ![]const u8 {
        return std.fmt.allocPrint(alloc, "error[{s}]: {s}", .{ rule, message });
    }

    /// Format a standard warning message.
    /// Returns: "warning[{rule}]: {message}"
    pub fn formatWarning(alloc: std.mem.Allocator, rule: []const u8, message: []const u8) ![]const u8 {
        return std.fmt.allocPrint(alloc, "warning[{s}]: {s}", .{ rule, message });
    }

    /// Format an error with context.
    /// Returns: "error[{rule}]: {message} in {context}"
    pub fn formatErrorWithContext(alloc: std.mem.Allocator, rule: []const u8, message: []const u8, context: []const u8) ![]const u8 {
        return std.fmt.allocPrint(alloc, "error[{s}]: {s} in {s}", .{ rule, message, context });
    }

    /// Format a warning with context.
    /// Returns: "warning[{rule}]: {message} in {context}"
    pub fn formatWarningWithContext(alloc: std.mem.Allocator, rule: []const u8, message: []const u8, context: []const u8) ![]const u8 {
        return std.fmt.allocPrint(alloc, "warning[{s}]: {s} in {s}", .{ rule, message, context });
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

/// Print a simple error message (no rule code).
pub fn printErr(message: []const u8) void {
    std.debug.print("error: {s}\n", .{message});
}

/// Print a simple warning message (no rule code).
pub fn printWarn(message: []const u8) void {
    std.debug.print("warning: {s}\n", .{message});
}

/// Print a success message to stderr.
pub fn printOk(message: []const u8) void {
    std.debug.print("{s}\n", .{message});
}

// ─── Tests ────────────────────────────────────────────────────

test "ErrorFormatter.formatError" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try ErrorFormatter.formatError(arena.allocator(), "E001", "file not found");
    try std.testing.expectEqualStrings("error[E001]: file not found", result);
}

test "ErrorFormatter.formatWarning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try ErrorFormatter.formatWarning(arena.allocator(), "W001", "unused variable");
    try std.testing.expectEqualStrings("warning[W001]: unused variable", result);
}

test "ErrorFormatter.formatErrorWithContext" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try ErrorFormatter.formatErrorWithContext(arena.allocator(), "E002", "parse error", "input.ss");
    try std.testing.expectEqualStrings("error[E002]: parse error in input.ss", result);
}

test "ErrorFormatter.formatWarningWithContext" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try ErrorFormatter.formatWarningWithContext(arena.allocator(), "W002", "deprecated syntax", "schema.ss");
    try std.testing.expectEqualStrings("warning[W002]: deprecated syntax in schema.ss", result);
}
