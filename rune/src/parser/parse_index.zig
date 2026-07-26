const std = @import("std");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;

/// Parse index declaration: `@ [u|f] [name] (field1, field2, ...)`
/// Supports 3 forms:
///   1. Shorthand: `@ field1 field2` (auto-generate name)
///   2. Composite: `@ (field1, field2)` (auto-generate name)
///   3. Full: `@ idx_name (field1, field2)`
pub fn parseIndex(alloc: std.mem.Allocator, line: tk.Line) !IndexDecl {
    var kind: IndexType = .regular;
    var name: []const u8 = "";
    var fields = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    var descending = try std.ArrayList(bool).initCapacity(alloc, 8);

    const tokens = line.tokens;
    var idx: usize = 1;

    if (idx < tokens.len) {
        if (std.mem.eql(u8, tokens[idx], "u")) {
            kind = .unique;
            idx += 1;
        } else if (std.mem.eql(u8, tokens[idx], "f")) {
            kind = .fulltext;
            idx += 1;
        }
    }

    if (idx < tokens.len) {
        // Composite index without name: @ (a, b) → auto-generate name
        if (std.mem.eql(u8, tokens[idx], "(")) {
            idx += 1; // skip (
            while (idx < tokens.len) : (idx += 1) {
                const tok = tokens[idx];
                if (std.mem.eql(u8, tok, ")")) break;
                if (std.mem.eql(u8, tok, ",")) continue;
                const is_desc = std.mem.endsWith(u8, tok, "-");
                const fname = if (is_desc) tok[0 .. tok.len - 1] else tok;
                try fields.append(alloc, try alloc.dupe(u8, fname));
                try descending.append(alloc, is_desc);
            }
            // Auto-generate name from fields: idx_field1_field2
            if (fields.items.len > 0) {
                const prefix = switch (kind) {
                    .regular => "idx_",
                    .unique => "uk_",
                    .fulltext => "ft_",
                    .primary_key => unreachable,
                };
                var name_buf = try std.ArrayList(u8).initCapacity(alloc, 64);
                try name_buf.appendSlice(alloc, prefix);
                for (fields.items, 0..) |f, fi| {
                    if (fi > 0) try name_buf.append(alloc, '_');
                    try name_buf.appendSlice(alloc, f);
                }
                name = try name_buf.toOwnedSlice(alloc);
            }
            return .{
                .kind = kind,
                .name = name,
                .fields = try fields.toOwnedSlice(alloc),
                .descending = try descending.toOwnedSlice(alloc),
                .line_no = line.line_no,
            };
        }

        // Peek ahead: if next token is NOT "(" or end, this is shorthand form
        // e.g., "@ name" where "name" is a field, not an index name
        const is_shorthand = (idx + 1 >= tokens.len) or
            !std.mem.eql(u8, tokens[idx + 1], "(");

        if (is_shorthand) {
            // Shorthand: @ field [field2 ...] → auto-generate index name
            while (idx < tokens.len) {
                const tok = tokens[idx];
                if (std.mem.eql(u8, tok, "(") or std.mem.eql(u8, tok, ",") or std.mem.eql(u8, tok, ")")) break;
                const is_desc = std.mem.endsWith(u8, tok, "-");
                const fname = if (is_desc) tok[0 .. tok.len - 1] else tok;
                try fields.append(alloc, try alloc.dupe(u8, fname));
                try descending.append(alloc, is_desc);
                idx += 1;
            }
            // Auto-generate name: idx_ / uk_ / ft_ + fields joined by _
            const prefix = switch (kind) {
                .regular => "idx_",
                .unique => "uk_",
                .fulltext => "ft_",
                .primary_key => unreachable,
            };
            var name_buf = try std.ArrayList(u8).initCapacity(alloc, 64);
            try name_buf.appendSlice(alloc, prefix);
            for (fields.items, 0..) |f, fi| {
                if (fi > 0) try name_buf.append(alloc, '_');
                try name_buf.appendSlice(alloc, f);
            }
            name = try name_buf.toOwnedSlice(alloc);
            return .{
                .kind = kind,
                .name = name,
                .fields = try fields.toOwnedSlice(alloc),
                .descending = try descending.toOwnedSlice(alloc),
                .line_no = line.line_no,
            };
        } else {
            // Full form: @ idx_name (field1, field2)
            name = try alloc.dupe(u8, tokens[idx]);
            idx += 1;
        }
    }

    while (idx < tokens.len) : (idx += 1) {
        const tok = tokens[idx];
        if (std.mem.eql(u8, tok, "(")) {
            continue;
        } else if (std.mem.eql(u8, tok, ")")) {
            break;
        } else if (std.mem.eql(u8, tok, ",")) {
            continue;
        } else {
            // Strip trailing ) if present
            var field_name = if (tok.len > 1 and tok[tok.len - 1] == ')')
                tok[0 .. tok.len - 1]
            else
                tok;
            const is_desc = std.mem.endsWith(u8, field_name, "-");
            if (is_desc) field_name = field_name[0 .. field_name.len - 1];
            try fields.append(alloc, try alloc.dupe(u8, field_name));
            try descending.append(alloc, is_desc);
        }
    }

    return .{
        .kind = kind,
        .name = name,
        .fields = try fields.toOwnedSlice(alloc),
        .descending = try descending.toOwnedSlice(alloc),
        .line_no = line.line_no,
    };
}

/// Parse composite primary key: `! field1, field2, ...`
pub fn parseCompositePk(alloc: std.mem.Allocator, line: tk.Line) !IndexDecl {
    var fields = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    var descending = try std.ArrayList(bool).initCapacity(alloc, 8);
    for (line.tokens) |tok| {
        if (std.mem.eql(u8, tok, "!") or std.mem.eql(u8, tok, ",")) continue;
        const is_desc = std.mem.endsWith(u8, tok, "-");
        const fname = if (is_desc) tok[0 .. tok.len - 1] else tok;
        try fields.append(alloc, try alloc.dupe(u8, fname));
        try descending.append(alloc, is_desc);
    }
    return .{
        .kind = .primary_key,
        .name = "",
        .fields = try fields.toOwnedSlice(alloc),
        .descending = try descending.toOwnedSlice(alloc),
        .line_no = line.line_no,
    };
}

// ─── Unit Tests ──────────────────────────────────────────────

fn makeLine(tokens: []const []const u8, line_no: usize) tk.Line {
    return .{
        .line_type = .Index,
        .tokens = tokens,
        .raw = "",
        .trimmed = "",
        .line_no = line_no,
    };
}

test "parseIndex: shorthand — @ field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "user_id" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_user_id", idx.name);
    try std.testing.expectEqual(@as(usize, 1), idx.fields.len);
    try std.testing.expectEqualStrings("user_id", idx.fields[0]);
}

test "parseIndex: shorthand — @ field1 field2" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "org_id", "user_id" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqualStrings("idx_org_id_user_id", idx.name);
    try std.testing.expectEqual(@as(usize, 2), idx.fields.len);
}

test "parseIndex: unique — @ u field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "u", "email" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.unique, idx.kind);
    try std.testing.expectEqualStrings("uk_email", idx.name);
}

test "parseIndex: fulltext — @ f field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "f", "bio" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.fulltext, idx.kind);
    try std.testing.expectEqualStrings("ft_bio", idx.name);
}

test "parseIndex: composite without name — @ (a, b)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "(", "a", ",", "b", ")" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_a_b", idx.name);
    try std.testing.expectEqual(@as(usize, 2), idx.fields.len);
    try std.testing.expectEqualStrings("a", idx.fields[0]);
    try std.testing.expectEqualStrings("b", idx.fields[1]);
}

test "parseIndex: full form — @ idx_name (field1, field2)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "idx_created", "(", "created_at", ")" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_created", idx.name);
    try std.testing.expectEqual(@as(usize, 1), idx.fields.len);
    try std.testing.expectEqualStrings("created_at", idx.fields[0]);
}

test "parseIndex: descending field — @ field-" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "created_at-" };
    const idx = try parseIndex(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.name);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqualStrings("idx_created_at", idx.name);
    try std.testing.expectEqualStrings("created_at", idx.fields[0]);
    try std.testing.expectEqual(true, idx.descending[0]);
}

test "parseCompositePk: ! a, b, c" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "!", "a", ",", "b", ",", "c" };
    const idx = try parseCompositePk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.primary_key, idx.kind);
    try std.testing.expectEqual(@as(usize, 3), idx.fields.len);
    try std.testing.expectEqualStrings("a", idx.fields[0]);
    try std.testing.expectEqualStrings("b", idx.fields[1]);
    try std.testing.expectEqualStrings("c", idx.fields[2]);
}
