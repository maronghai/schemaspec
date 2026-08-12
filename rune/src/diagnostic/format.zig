const std = @import("std");

// ─── Standardized Error Formatting ────────────────────────────
// Consistent error message format across all modules.
// Format: "error[rule]: message" or "warning[rule]: message"

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

test "printError" {
    // Smoke test — just verify it doesn't crash
    printError("E001", "file not found");
}

test "printWarn" {
    printWarn("W001");
}

test "printErrorWithContext" {
    printErrorWithContext("E002", "parse error", "input.ss");
}

test "printOk" {
    printOk("success message");
}
