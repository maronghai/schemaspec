const std = @import("std");
const tk = @import("tokenizer.zig");
const diag = @import("../semantic/diagnostic.zig");
const ast_mod = @import("../types/ast.zig");
const SourceLocation = ast_mod.SourceLocation;

// ─── Parse Recovery: error handling ──────────────────────────
//
// Extracted from parser.zig in v0.4.74 Phase 1.
// Provides error recording for the forward parser.

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

/// Compute SourceLocation from a tokenized line and a token within it.
pub fn locFromLine(line: tk.Line, tok: []const u8) SourceLocation {
    const col = diag.tokenColumn(tok, line.raw);
    return .{
        .line = line.line_no,
        .col = col,
        .offset = line.offset + col - 1,
    };
}
