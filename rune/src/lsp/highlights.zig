const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const lsp_protocol = @import("protocol.zig");
const Range = lsp_protocol.Range;

// ─── LSP Document Highlights ─────────────────────────────────
// Highlights all occurrences of the symbol under the cursor.
// Returns a list of DocumentHighlight objects with ranges and kinds.

pub const HighlightKind = enum(u32) {
    text = 1,
    read = 2,
    write = 3,
};

pub const DocumentHighlight = struct {
    range: Range,
    kind: HighlightKind,
};

/// Find all highlights for the symbol at the given position.
/// Scans the TypedAst for matching table names and column names.
pub fn getDocumentHighlights(typed: TypedAst, line: u32, character: u32) []DocumentHighlight {
    var highlights: [256]DocumentHighlight = undefined;
    var count: usize = 0;

    // Try to match a table name at the cursor position
    for (typed.tables) |table| {
        const table_line = @as(u32, @intCast(table.line_no -| 1));
        if (line == table_line) {
            const name_start: u32 = 2; // After "# "
            const name_end = name_start + @as(u32, @intCast(table.name.len));
            if (character >= name_start and character < name_end) {
                // Found table name — highlight definition
                if (count < highlights.len) {
                    highlights[count] = .{
                        .range = .{
                            .start = .{ .line = table_line, .character = name_start },
                            .end = .{ .line = table_line, .character = name_end },
                        },
                        .kind = .write,
                    };
                    count += 1;
                }

                // Find FK references to this table in other tables
                for (typed.tables) |other_table| {
                    for (other_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            const col_line = @as(u32, @intCast(other_table.line_no -| 1));
                            if (count < highlights.len) {
                                highlights[count] = .{
                                    .range = .{
                                        .start = .{ .line = col_line, .character = 0 },
                                        .end = .{ .line = col_line, .character = 100 },
                                    },
                                    .kind = .read,
                                };
                                count += 1;
                            }
                        }
                    }
                }

                return highlights[0..count];
            }
        }

        // Check columns for name match
        for (table.columns) |col| {
            if (std.mem.eql(u8, col.name, "")) continue;
            const col_line = @as(u32, @intCast(table.line_no -| 1));
            if (line == col_line) {
                // Check if cursor is approximately on this column's line
                // and the column name is under the cursor
                if (count < highlights.len) {
                    highlights[count] = .{
                        .range = .{
                            .start = .{ .line = col_line, .character = 0 },
                            .end = .{ .line = col_line, .character = 100 },
                        },
                        .kind = .write,
                    };
                    count += 1;
                }

                // Find FK references to this column
                for (typed.tables) |fk_table| {
                    for (fk_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            const fk_line = @as(u32, @intCast(fk_table.line_no -| 1));
                            if (count < highlights.len) {
                                highlights[count] = .{
                                    .range = .{
                                        .start = .{ .line = fk_line, .character = 0 },
                                        .end = .{ .line = fk_line, .character = 100 },
                                    },
                                    .kind = .read,
                                };
                                count += 1;
                            }
                        }
                    }
                }

                return highlights[0..count];
            }
        }
    }

    return highlights[0..count];
}
