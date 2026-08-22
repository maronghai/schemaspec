const std = @import("std");

// ─── Standardized Error Formatting ────────────────────────────
// Consistent error message format across all modules.
// Format: "error[rule]: message" or "warning[rule]: message"
//
// Each printer has a `To(writer)` variant; the plain versions delegate to
// one targeting stderr. Tests use the `To` variants with an in-memory
// buffer so `zig build test` output stays clean.

/// Write a standardized error to the given writer.
pub fn printErrorTo(writer: *std.Io.Writer, rule: []const u8, message: []const u8) !void {
    try writer.print("error[{s}]: {s}\n", .{ rule, message });
}

/// Write a standardized warning to the given writer.
pub fn printWarningTo(writer: *std.Io.Writer, rule: []const u8, message: []const u8) !void {
    try writer.print("warning[{s}]: {s}\n", .{ rule, message });
}

/// Write a standardized error with context to the given writer.
pub fn printErrorWithContextTo(writer: *std.Io.Writer, rule: []const u8, message: []const u8, context: []const u8) !void {
    try writer.print("error[{s}]: {s} in {s}\n", .{ rule, message, context });
}

/// Write a standardized warning with context to the given writer.
pub fn printWarningWithContextTo(writer: *std.Io.Writer, rule: []const u8, message: []const u8, context: []const u8) !void {
    try writer.print("warning[{s}]: {s} in {s}\n", .{ rule, message, context });
}

/// Write a simple error message (no rule code) to the given writer.
pub fn printErrTo(writer: *std.Io.Writer, message: []const u8) !void {
    try writer.print("error: {s}\n", .{message});
}

/// Write a simple warning message (no rule code) to the given writer.
pub fn printWarnTo(writer: *std.Io.Writer, message: []const u8) !void {
    try writer.print("warning: {s}\n", .{message});
}

/// Write a success message to the given writer.
pub fn printOkTo(writer: *std.Io.Writer, message: []const u8) !void {
    try writer.print("{s}\n", .{message});
}

/// Print a standardized error to stderr.
pub fn printError(rule: []const u8, message: []const u8) void {
    printToStderr(printErrorTo, .{ rule, message });
}

/// Print a standardized warning to stderr.
pub fn printWarning(rule: []const u8, message: []const u8) void {
    printToStderr(printWarningTo, .{ rule, message });
}

/// Print a standardized error with context to stderr.
pub fn printErrorWithContext(rule: []const u8, message: []const u8, context: []const u8) void {
    printToStderr(printErrorWithContextTo, .{ rule, message, context });
}

/// Print a standardized warning with context to stderr.
pub fn printWarningWithContext(rule: []const u8, message: []const u8, context: []const u8) void {
    printToStderr(printWarningWithContextTo, .{ rule, message, context });
}

/// Print a simple error message (no rule code).
pub fn printErr(message: []const u8) void {
    printToStderr(printErrTo, .{message});
}

/// Print a simple warning message (no rule code).
pub fn printWarn(message: []const u8) void {
    printToStderr(printWarnTo, .{message});
}

/// Print a success message to stderr.
pub fn printOk(message: []const u8) void {
    printToStderr(printOkTo, .{message});
}

fn printToStderr(comptime writeFn: anytype, args: anytype) void {
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    @call(.auto, writeFn, .{&w} ++ args) catch return;
    w.flush() catch return;
    std.debug.print("{s}", .{w.buffered()});
}

// ─── Tests ────────────────────────────────────────────────────

test "printErrorTo formats rule and message" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printErrorTo(&w, "E001", "file not found");
    try std.testing.expectEqualStrings("error[E001]: file not found\n", w.buffered());
}

test "printWarnTo formats rule and message" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printWarnTo(&w, "something suspicious");
    try std.testing.expectEqualStrings("warning: something suspicious\n", w.buffered());
}

test "printWarningTo formats rule and message" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printWarningTo(&w, "W001", "something suspicious");
    try std.testing.expectEqualStrings("warning[W001]: something suspicious\n", w.buffered());
}

test "printErrorWithContextTo includes context path" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printErrorWithContextTo(&w, "E002", "parse error", "input.ss");
    try std.testing.expectEqualStrings("error[E002]: parse error in input.ss\n", w.buffered());
}

test "printErrTo omits rule code" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printErrTo(&w, "boom");
    try std.testing.expectEqualStrings("error: boom\n", w.buffered());
}

test "printOkTo writes bare message" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try printOkTo(&w, "success message");
    try std.testing.expectEqualStrings("success message\n", w.buffered());
}

test "stderr printers swallow overflow without crashing" {
    // 512-byte fixed buffer; long messages must not crash the caller.
    printError("E001", "x" ** 1024);
    printWarningWithContext("W002", "y" ** 1024, "z" ** 1024);
}
