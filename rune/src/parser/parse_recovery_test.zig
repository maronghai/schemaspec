const std = @import("std");
const recovery = @import("parse_recovery.zig");
const tk = @import("tokenizer.zig");
const diag = @import("../semantic/diagnostic.zig");
const ast_mod = @import("../types/ast.zig");
const LineType = tk.LineType;

const testing = std.testing;

fn makeLine(line_type: LineType, line_no: usize) tk.Line {
    return .{
        .line_type = line_type,
        .tokens = &.{},
        .raw = "example line",
        .trimmed = "example line",
        .line_no = line_no,
    };
}

// ─── handleParseError ────────────────────────────────────────

test "handleParseError: records error when diagnostics enabled" {
    const alloc = testing.allocator;
    var dc = try diag.DiagnosticCollector.init(alloc);
    defer dc.diagnostics.deinit(alloc);

    const line = makeLine(.Table, 5);
    const continued = recovery.handleParseError(&dc, error.ParseError, line, "test error message");
    try testing.expectEqual(true, continued);
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 1), dc.errorCount());
}

test "handleParseError: returns false when diagnostics is null" {
    const line = makeLine(.Table, 5);
    const continued = recovery.handleParseError(null, error.ParseError, line, "test error message");
    try testing.expectEqual(false, continued);
}

test "handleParseError: accumulates multiple errors" {
    const alloc = testing.allocator;
    var dc = try diag.DiagnosticCollector.init(alloc);
    defer dc.diagnostics.deinit(alloc);

    const line1 = makeLine(.Table, 3);
    const line2 = makeLine(.Template, 7);
    _ = recovery.handleParseError(&dc, error.ParseError, line1, "first error");
    _ = recovery.handleParseError(&dc, error.ParseError, line2, "second error");
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 2), dc.errorCount());
}

// ─── isBlockBoundary ─────────────────────────────────────────

test "isBlockBoundary: returns true for block-starting types" {
    try testing.expectEqual(true, recovery.isBlockBoundary(.Schema));
    try testing.expectEqual(true, recovery.isBlockBoundary(.Template));
    try testing.expectEqual(true, recovery.isBlockBoundary(.Table));
    try testing.expectEqual(true, recovery.isBlockBoundary(.View));
    try testing.expectEqual(true, recovery.isBlockBoundary(.TypeDef));
}

test "isBlockBoundary: returns false for non-boundary types" {
    try testing.expectEqual(false, recovery.isBlockBoundary(.Field));
    try testing.expectEqual(false, recovery.isBlockBoundary(.FK));
    try testing.expectEqual(false, recovery.isBlockBoundary(.Index));
    try testing.expectEqual(false, recovery.isBlockBoundary(.Slot));
    try testing.expectEqual(false, recovery.isBlockBoundary(.CompositePK));
    try testing.expectEqual(false, recovery.isBlockBoundary(.Empty));
}

// ─── findNextBlockBoundary ───────────────────────────────────

test "findNextBlockBoundary: finds next Table boundary" {
    const lines = [_]tk.Line{
        makeLine(.Field, 1),
        makeLine(.Field, 2),
        makeLine(.Table, 3),
        makeLine(.Field, 4),
    };
    const result = recovery.findNextBlockBoundary(&lines, 0);
    try testing.expectEqual(@as(?usize, 2), result);
}

test "findNextBlockBoundary: finds first boundary at start" {
    const lines = [_]tk.Line{
        makeLine(.Schema, 1),
        makeLine(.Field, 2),
    };
    const result = recovery.findNextBlockBoundary(&lines, 0);
    try testing.expectEqual(@as(?usize, 0), result);
}

test "findNextBlockBoundary: returns null when no boundary found" {
    const lines = [_]tk.Line{
        makeLine(.Field, 1),
        makeLine(.FK, 2),
        makeLine(.Index, 3),
    };
    const result = recovery.findNextBlockBoundary(&lines, 0);
    try testing.expectEqual(@as(?usize, null), result);
}

test "findNextBlockBoundary: returns null for empty lines" {
    const lines = [_]tk.Line{};
    const result = recovery.findNextBlockBoundary(&lines, 0);
    try testing.expectEqual(@as(?usize, null), result);
}

test "findNextBlockBoundary: skips past start index" {
    const lines = [_]tk.Line{
        makeLine(.Template, 1),
        makeLine(.Field, 2),
        makeLine(.Table, 3),
    };
    // Start from index 1, should find Table at index 2
    const result = recovery.findNextBlockBoundary(&lines, 1);
    try testing.expectEqual(@as(?usize, 2), result);
}

// ─── locFromLine ─────────────────────────────────────────────

test "locFromLine: computes correct location" {
    var line = makeLine(.Table, 10);
    line.raw = "  id users s32 !";
    const tok = "id";
    const loc = recovery.locFromLine(line, tok);
    try testing.expectEqual(@as(usize, 10), loc.line);
    // col should be 3 (after "  " + 1-based)
    try testing.expect(loc.col >= 3 and loc.col <= 4);
}
