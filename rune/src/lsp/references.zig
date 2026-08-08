const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const lsp_protocol = @import("protocol.zig");
const Range = lsp_protocol.Range;
const Location = lsp_protocol.Location;
const getLineText = @import("helpers.zig").getLineText;

// ─── LSP Find References ─────────────────────────────────────
// Finds all references to a table or column name in the document.
// Returns a list of Location objects pointing to each reference.

pub const Reference = struct {
    range: Range,
    /// True if this reference is the definition (table header or column declaration).
    is_definition: bool,
};

/// Find all references to the symbol at the given position.
/// Scans the TypedAst for table names, column names, and FK references.
pub fn getReferences(alloc: std.mem.Allocator, typed: TypedAst, line: u32, character: u32, uri: []const u8, doc_text: []const u8) []Reference {
    _ = uri; // URI used for Location construction in callers
    var refs = std.ArrayList(Reference).initCapacity(alloc, 64) catch return &.{};
    defer refs.deinit(alloc);

    // First, try to match a table name at the cursor position
    for (typed.tables) |table| {
        // Check if cursor is on the table name line
        const table_line = @as(u32, @intCast(table.line_no -| 1));
        if (line == table_line) {
            // Check if cursor is within the table name range
            const name_start: u32 = 2; // After "# "
            const name_end = name_start + @as(u32, @intCast(table.name.len));
            if (character >= name_start and character < name_end) {
                // Found table name reference — add definition
                refs.append(alloc, .{
                    .range = .{
                        .start = .{ .line = table_line, .character = name_start },
                        .end = .{ .line = table_line, .character = name_end },
                    },
                    .is_definition = true,
                }) catch {};

                // Find FK references to this table
                for (typed.tables) |other_table| {
                    for (other_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            const fk_line = @as(u32, @intCast(other_table.line_no -| 1));
                            const line_len = @as(u32, @intCast(getLineText(doc_text, fk_line).len));
                            refs.append(alloc, .{
                                .range = .{
                                    .start = .{ .line = fk_line, .character = 0 },
                                    .end = .{ .line = fk_line, .character = line_len },
                                },
                                .is_definition = false,
                            }) catch {};
                        }
                    }
                }

                return refs.toOwnedSlice(alloc) catch &.{};
            }
        }

        // Check columns for name match at cursor position
        for (table.columns) |col| {
            const col_line = @as(u32, @intCast(table.line_no -| 1));
            if (line == col_line) {
                if (std.mem.eql(u8, col.name, "")) continue;

                // Find all references to this column in FK declarations
                for (typed.tables) |fk_table| {
                    for (fk_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            const line_len = @as(u32, @intCast(getLineText(doc_text, col_line).len));
                            refs.append(alloc, .{
                                .range = .{
                                    .start = .{ .line = col_line, .character = 0 },
                                    .end = .{ .line = col_line, .character = line_len },
                                },
                                .is_definition = false,
                            }) catch {};
                        }
                    }
                }
            }
        }
    }

    return refs.toOwnedSlice(alloc) catch &.{};
}
