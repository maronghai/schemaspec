const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const TextEdit = protocol.TextEdit;
const makeRange = @import("helpers.zig").makeRange;

// ─── Rename ──────────────────────────────────────────────

/// Result of a rename operation: list of edits to apply.
pub const RenameResult = struct {
    changes: []const TextEdit,
};

/// Check if rename is valid at the given position.
pub fn prepareRename(ast: TypedAst, position: Position, doc_text: []const u8) ?[]const u8 {
    const line = position.line;
    const character = position.character;

    var line_start: usize = 0;
    var current_line: u32 = 0;
    for (doc_text, 0..) |c, i| {
        if (current_line == line) {
            const line_text = doc_text[line_start..i];
            if (character > line_text.len) return null;
            const before_cursor = line_text[0..character];
            var word_end = before_cursor.len;
            while (word_end > 0) : (word_end -= 1) {
                const wc = before_cursor[word_end - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            var word_start = word_end;
            while (word_start > 0) : (word_start -= 1) {
                const wc = before_cursor[word_start - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            const word = before_cursor[word_start..word_end];
            if (word.len == 0) return null;

            for (ast.tables) |table| {
                if (std.mem.eql(u8, table.name, word)) return word;
                for (table.columns) |col| {
                    if (std.mem.eql(u8, col.name, word)) return word;
                }
            }
            return null;
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }
    return null;
}

/// Find all references to a symbol at the given position and return rename edits.
pub fn getRenameLinks(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: []const u8, new_name: []const u8) ?RenameResult {
    const line = position.line;
    const character = position.character;

    var line_start: usize = 0;
    var current_line: u32 = 0;
    var old_name: ?[]const u8 = null;
    for (doc_text, 0..) |c, i| {
        if (current_line == line) {
            const line_text = doc_text[line_start..i];
            if (character > line_text.len) return null;
            const before_cursor = line_text[0..character];
            var word_end = before_cursor.len;
            while (word_end > 0) : (word_end -= 1) {
                const wc = before_cursor[word_end - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            var word_start = word_end;
            while (word_start > 0) : (word_start -= 1) {
                const wc = before_cursor[word_start - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            old_name = before_cursor[word_start..word_end];
            break;
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }

    const name = old_name orelse return null;
    var edits = std.ArrayList(TextEdit).initCapacity(alloc, 16) catch return null;

    line_start = 0;
    current_line = 0;
    for (doc_text, 0..) |c, i| {
        const is_last = i == doc_text.len - 1;
        const line_text = if (is_last) doc_text[line_start..] else doc_text[line_start..i];

        var search_start: usize = 0;
        while (search_start < line_text.len) {
            const pos = std.mem.indexOf(u8, line_text[search_start..], name) orelse break;
            const abs_pos = search_start + pos;

            const before_ok = abs_pos == 0 or !std.ascii.isAlphanumeric(doc_text[line_start + abs_pos - 1]);
            const after_end = line_start + abs_pos + name.len;
            const after_ok = after_end >= doc_text.len or !std.ascii.isAlphanumeric(doc_text[after_end]);

            if (before_ok and after_ok) {
                const is_table_decl = isTableDeclaration(line_text, name);
                const is_fk_ref = isFkReference(line_text, name, ast);

                if (is_table_decl or is_fk_ref) {
                    edits.append(alloc, .{
                        .range = makeRange(current_line, @intCast(abs_pos), current_line, @intCast(abs_pos + name.len)),
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

    if (edits.items.len == 0) return null;
    return .{ .changes = edits.items };
}

fn isTableDeclaration(line_text: []const u8, name: []const u8) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, "table ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "template ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "view ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    return false;
}

fn isFkReference(line_text: []const u8, name: []const u8, ast: TypedAst) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    if (std.mem.indexOf(u8, trimmed, "FK") == null) return false;
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
