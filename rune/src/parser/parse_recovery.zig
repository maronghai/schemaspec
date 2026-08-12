const std = @import("std");
const tk = @import("tokenizer.zig");
const diag = @import("../diagnostic.zig");
const ast_mod = @import("../types/ast.zig");
const SourceLocation = ast_mod.SourceLocation;
const LineType = tk.LineType;
pub const locFromLine = @import("loc.zig").locFromLine;

// ─── Parse Recovery: error handling ──────────────────────────
//
// Extracted from parser.zig in v0.4.74 Phase 1.
// Provides error recording and synchronizing-token recovery
// for the forward parser.

/// Record a parse error via DiagnosticCollector.
/// Returns true if error was recorded (caller should continue),
/// false to propagate the error to the caller.
pub fn handleParseError(
    diagnostics: ?*diag.DiagnosticCollector,
    err: anyerror,
    line: tk.Line,
    comptime message: []const u8,
) bool {
    if (diagnostics) |dc| {
        dc.record(.{
            .severity = .@"error",
            .line_no = line.line_no,
            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
            .message = message,
            .actual = @errorName(err),
            .source_line = line.raw,
        });
        return true;
    }
    return false;
}

/// Check if a LineType starts a new block (template, table, view, schema, typedef).
/// Used for synchronizing-token recovery: after a header parse error,
/// skip lines until we hit the next block boundary.
pub fn isBlockBoundary(lt: LineType) bool {
    return switch (lt) {
        .Schema, .Template, .Table, .View, .TypeDef => true,
        else => false,
    };
}

/// Find the index of the next block boundary in the lines array starting from `start`.
/// Returns null if no boundary is found (end of input).
pub fn findNextBlockBoundary(lines: []const tk.Line, start: usize) ?usize {
    var i = start;
    while (i < lines.len) : (i += 1) {
        if (isBlockBoundary(lines[i].line_type)) return i;
    }
    return null;
}
