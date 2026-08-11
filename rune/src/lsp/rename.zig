const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const TextEdit = protocol.TextEdit;
const makeRange = @import("helpers.zig").makeRange;
const wordAtPosition = @import("helpers.zig").wordAtPosition;

// ─── Rename ──────────────────────────────────────────────

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
pub fn getRenameLinks(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: []const u8, new_name: []const u8) ?RenameResult {
    const old_name = wordAtPosition(doc_text, position.line, position.character) orelse return null;

    var edits = std.ArrayList(TextEdit).initCapacity(alloc, 16) catch return null;

    var line_start: usize = 0;
    var current_line: u32 = 0;
    for (doc_text, 0..) |c, i| {
        const is_last = i == doc_text.len - 1;
        const line_text = if (is_last) doc_text[line_start..] else doc_text[line_start..i];

        var search_start: usize = 0;
        while (search_start < line_text.len) {
            const pos = std.mem.indexOf(u8, line_text[search_start..], old_name) orelse break;
            const abs_pos = search_start + pos;

            const before_ok = abs_pos == 0 or !std.ascii.isAlphanumeric(doc_text[line_start + abs_pos - 1]);
            const after_end = line_start + abs_pos + old_name.len;
            const after_ok = after_end >= doc_text.len or !std.ascii.isAlphanumeric(doc_text[after_end]);

            if (before_ok and after_ok) {
                const is_table_decl = isTableDeclaration(line_text, old_name);
                const is_fk_ref = isFkReference(line_text, old_name, ast);

                if (is_table_decl or is_fk_ref) {
                    edits.append(alloc, .{
                        .range = makeRange(current_line, @intCast(abs_pos), current_line, @intCast(abs_pos + old_name.len)),
                        .new_text = new_name,
                    }) catch {};
                }
            }

            search_start = abs_pos + 1;
        }

        if (c == '\n' or is_last) {
            line_start = i + 1;
            current_line += 1;
        }
    }

    if (edits.items.len == 0) {
        edits.deinit(alloc);
        return null;
    }
    return .{ .changes = edits.toOwnedSlice(alloc) catch return null };
}

fn isTableDeclaration(line_text: []const u8, name: []const u8) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    // Rune syntax: # table_name { ... }  or  % template_name { ... }  or  & view_name { ... }
    if (trimmed.len > 0 and (trimmed[0] == '#' or trimmed[0] == '%' or trimmed[0] == '&')) {
        if (std.mem.indexOf(u8, trimmed, name) != null) return true;
    }
    // Also support SQL DDL syntax: table_name, template_name, view_name
    if (std.mem.startsWith(u8, trimmed, "table ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "template ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "view ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    return false;
}

fn isFkReference(line_text: []const u8, name: []const u8, ast: TypedAst) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    // Rune syntax uses -> for FK references, not "FK" keyword
    const has_fk_indicator = std.mem.indexOf(u8, trimmed, "->") != null or std.mem.indexOf(u8, trimmed, "FK") != null;
    if (!has_fk_indicator) return false;
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            if (std.mem.eql(u8, fk.ref_table, name)) return true;
            for (fk.ref_fields) |rf| {
                if (std.mem.eql(u8, rf, name)) return true;
            }
            for (fk.fields) |f| {
                if (std.mem.eql(u8, f, name)) return true;
            }
        }
    }
    return false;
}
