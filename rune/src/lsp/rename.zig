const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const TextEdit = protocol.TextEdit;
const makeRange = @import("helpers.zig").makeRange;
const wordAtPosition = @import("helpers.zig").wordAtPosition;
const lineNoToZeroBased = @import("helpers.zig").lineNoToZeroBased;

// ─── Rename ──────────────────────────────────────────────
// Renaming is AST-driven: the symbol under the cursor must be a known table
// or column name, and edits are emitted only for positions the AST knows
// about (declarations, FK reference lines). Free-text scanning of the whole
// document would corrupt comments and unrelated words.

/// Result of a rename operation: list of edits to apply.
pub const RenameResult = struct {
    changes: []const TextEdit,
};

/// Check if rename is valid at the given position.
pub fn prepareRename(ast: TypedAst, position: Position, doc_text: []const u8) ?[]const u8 {
    const word = wordAtPosition(doc_text, position.line, position.character) orelse return null;

    for (ast.tables) |table| {
        if (std.mem.eql(u8, table.name, word)) return word;
        for (table.columns) |col| {
            if (std.mem.eql(u8, col.name, word)) return word;
        }
    }
    return null;
}

/// Find all references to a symbol at the given position and return rename edits.
///
/// Edits cover:
/// - the table declaration line (rename target is a table)
/// - every FK line whose ref_table (or ref_fields, when renaming a column)
///   matches — Rune FK syntax is `user_id > users.id [-C]`
/// - column declarations when renaming a column
pub fn getRenameLinks(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: []const u8, new_name: []const u8) ?RenameResult {
    const old_name = wordAtPosition(doc_text, position.line, position.character) orelse return null;

    var is_table_rename = false;
    var is_column_rename = false;
    for (ast.tables) |table| {
        if (std.mem.eql(u8, table.name, old_name)) is_table_rename = true;
        for (table.columns) |col| {
            if (std.mem.eql(u8, col.name, old_name)) is_column_rename = true;
        }
    }
    if (!is_table_rename and !is_column_rename) return null;

    var edits = std.ArrayList(TextEdit).initCapacity(alloc, 16) catch return null;
    var seen = std.ArrayList([2]u32).initCapacity(alloc, 16) catch return null;
    defer seen.deinit(alloc);

    // Table declaration line(s).
    if (is_table_rename) {
        for (ast.tables) |table| {
            if (!std.mem.eql(u8, table.name, old_name)) continue;
            addEditForOccurrenceOnLine(alloc, &edits, &seen, doc_text, lineNoToZeroBased(table.line_no), old_name, new_name);
        }
    }

    // Column declaration line(s).
    if (is_column_rename) {
        for (ast.tables) |table| {
            for (table.columns) |col| {
                if (!std.mem.eql(u8, col.name, old_name)) continue;
                addEditForOccurrenceOnLine(alloc, &edits, &seen, doc_text, lineNoToZeroBased(col.line_no), old_name, new_name);
            }
        }
    }

    // FK lines referencing this table (ref_table token) or this column
    // (local field / referenced field names on the FK line).
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            const fk_line = lineNoToBased(fk.line_no);
            const renames_ref_table = is_table_rename and std.mem.eql(u8, fk.ref_table, old_name);
            var renames_field = false;
            if (is_column_rename) {
                for (fk.fields) |f| {
                    if (std.mem.eql(u8, f, old_name)) renames_field = true;
                }
                for (fk.ref_fields) |rf| {
                    if (std.mem.eql(u8, rf, old_name)) renames_field = true;
                }
            }
            if (!renames_ref_table and !renames_field) continue;
            // The FK's ref_table appears as a bare or dotted token on the FK
            // line; field names appear as leading tokens. One occurrence edit
            // per name per line is enough for either form.
            addEditForOccurrenceOnLine(alloc, &edits, &seen, doc_text, fk_line, old_name, new_name);
        }
    }

    if (edits.items.len == 0) {
        edits.deinit(alloc);
        return null;
    }
    return .{ .changes = edits.toOwnedSlice(alloc) catch return null };
}

fn lineNoToBased(line_no: usize) u32 {
    return lineNoToZeroBased(line_no);
}

/// Append one edit for the first whole-word occurrence of `old_name` on the
/// given 0-based line, unless that (line, char) cell was already claimed by a
/// previous edit. At most one edit per occurrence; no overlapping ranges.
fn addEditForOccurrenceOnLine(
    alloc: std.mem.Allocator,
    edits: *std.ArrayList(TextEdit),
    seen: *std.ArrayList([2]u32),
    doc_text: []const u8,
    line: u32,
    old_name: []const u8,
    new_name: []const u8,
) void {
    const helpers = @import("helpers.zig");
    const range = helpers.findNameInLine(doc_text, line, old_name) orelse return;
    const cell = [2]u32{ range.start.line, range.start.character };
    for (seen.items) |s| {
        if (s[0] == cell[0] and s[1] == cell[1]) return;
    }
    seen.append(alloc, cell) catch {};
    edits.append(alloc, .{
        .range = range,
        .new_text = new_name,
    }) catch {};
}
