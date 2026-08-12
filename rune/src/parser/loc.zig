const ast_mod = @import("../types/ast.zig");
const tk = @import("tokenizer.zig");
const diag = @import("../diagnostic.zig");

const SourceLocation = ast_mod.SourceLocation;

/// Compute SourceLocation from a tokenized line and a token within it.
/// Shared utility used by parser, parse_table, parse_template, and parse_recovery.
pub fn locFromLine(line: tk.Line, tok: []const u8) SourceLocation {
    const col = diag.tokenColumn(tok, line.raw);
    return .{
        .line = line.line_no,
        .col = col,
        .offset = line.offset + col - 1,
    };
}
