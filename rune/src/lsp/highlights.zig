const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const lsp_protocol = @import("protocol.zig");
const Range = lsp_protocol.Range;
const getLineText = @import("helpers.zig").getLineText;
const findNameInLine = @import("helpers.zig").findNameInLine;

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
pub fn getDocumentHighlights(alloc: std.mem.Allocator, typed: TypedAst, line: u32, character: u32, doc_text: []const u8) []DocumentHighlight {
    var highlights = std.ArrayList(DocumentHighlight).initCapacity(alloc, 64) catch return &.{};
    defer highlights.deinit(alloc);

    // Try to match a table name at the cursor position
    for (typed.tables) |table| {
        const table_line = @as(u32, @intCast(table.line_no -| 1));
        if (line == table_line) {
            const name_start: u32 = 2; // After "# "
            const name_end = name_start + @as(u32, @intCast(table.name.len));
            if (character >= name_start and character < name_end) {
                // Found table name — highlight definition
                highlights.append(alloc, .{
                    .range = .{
                        .start = .{ .line = table_line, .character = name_start },
                        .end = .{ .line = table_line, .character = name_end },
                    },
                    .kind = .write,
                }) catch {};

                // Find FK references to this table in other tables
                for (typed.tables) |other_table| {
                    for (other_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            const fk_line = @as(u32, @intCast(other_table.line_no -| 1));
                            if (fk.fields.len > 0) {
                                if (findNameInLine(doc_text, fk_line, fk.fields[0])) |range| {
                                    highlights.append(alloc, .{
                                        .range = range,
                                        .kind = .read,
                                    }) catch {};
                                }
                            }
                        }
                    }
                }

                return highlights.toOwnedSlice(alloc) catch &.{};
            }
        }

        // Check columns for name match
        for (table.columns) |col| {
            if (std.mem.eql(u8, col.name, "")) continue;
            const col_line = @as(u32, @intCast(table.line_no -| 1));
            if (line == col_line) {
                const line_len = @as(u32, @intCast(getLineText(doc_text, col_line).len));
                highlights.append(alloc, .{
                    .range = .{
                        .start = .{ .line = col_line, .character = 0 },
                        .end = .{ .line = col_line, .character = line_len },
                    },
                    .kind = .write,
                }) catch {};

                // Find FK references to this column
                for (typed.tables) |fk_table| {
                    for (fk_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            // Check if this FK references this specific column
                            if (fk.ref_fields.len > 0 and std.mem.eql(u8, fk.ref_fields[0], col.name)) {
                                const fk_line = @as(u32, @intCast(fk_table.line_no -| 1));
                                if (fk.fields.len > 0) {
                                    if (findNameInLine(doc_text, fk_line, fk.fields[0])) |range| {
                                        highlights.append(alloc, .{
                                            .range = range,
                                            .kind = .read,
                                        }) catch {};
                                    }
                                }
                            }
                        }
                    }
                }

                return highlights.toOwnedSlice(alloc) catch &.{};
            }
        }
    }

    return highlights.toOwnedSlice(alloc) catch &.{};
}
