const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const lsp_protocol = @import("protocol.zig");
const Range = lsp_protocol.Range;
const Location = lsp_protocol.Location;
const getLineText = @import("helpers.zig").getLineText;
const findNameInLine = @import("helpers.zig").findNameInLine;
const lineNoToZeroBased = @import("helpers.zig").lineNoToZeroBased;

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
                            // Locate the FK field name on the line the FK was
                            // declared on (not the table header line).
                            const fk_line = lineNoToZeroBased(fk.line_no);
                            if (fk.fields.len > 0) {
                                const field_name = fk.fields[0];
                                if (findNameInLine(doc_text, fk_line, field_name)) |range| {
                                    refs.append(alloc, .{
                                        .range = range,
                                        .is_definition = false,
                                    }) catch {};
                                }
                            }
                        }
                    }
                }

                return refs.toOwnedSlice(alloc) catch &.{};
            }
        }

        // Check columns for name match at cursor position
        for (table.columns) |col| {
            const col_line = @as(u32, @intCast(col.line_no -| 1));
            if (line == col_line) {
                if (std.mem.eql(u8, col.name, "")) continue;

                // Find FK references to this column in other tables
                for (typed.tables) |fk_table| {
                    for (fk_table.fks) |fk| {
                        if (std.mem.eql(u8, fk.ref_table, table.name)) {
                            // Check if this FK references this specific column
                            if (fk.ref_fields.len > 0 and std.mem.eql(u8, fk.ref_fields[0], col.name)) {
                                const fk_line = lineNoToZeroBased(fk.line_no);
                                if (fk.fields.len > 0) {
                                    if (findNameInLine(doc_text, fk_line, fk.fields[0])) |range| {
                                        refs.append(alloc, .{
                                            .range = range,
                                            .is_definition = false,
                                        }) catch {};
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return refs.toOwnedSlice(alloc) catch &.{};
}
