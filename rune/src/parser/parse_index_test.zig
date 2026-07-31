const std = @import("std");
const pi = @import("parse_index.zig");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;

const testing = std.testing;

fn makeLine(tokens: []const []const u8, line_no: usize) tk.Line {
    return .{
        .line_type = .Index,
        .tokens = tokens,
        .raw = "",
        .trimmed = "",
        .line_no = line_no,
    };
}

fn freeIndexDecl(alloc: std.mem.Allocator, idx: IndexDecl) void {
    alloc.free(idx.name);
    for (idx.fields) |f| alloc.free(f);
    alloc.free(idx.fields);
    alloc.free(idx.descending);
}

test "parseIndex: shorthand — @ field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "user_id" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_user_id", idx.name);
    try std.testing.expectEqual(@as(usize, 1), idx.fields.len);
    try std.testing.expectEqualStrings("user_id", idx.fields[0]);
}

test "parseIndex: shorthand — @ field1 field2" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "org_id", "user_id" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqualStrings("idx_org_id_user_id", idx.name);
    try std.testing.expectEqual(@as(usize, 2), idx.fields.len);
}

test "parseIndex: unique — @ u field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "u", "email" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqual(IndexType.unique, idx.kind);
    try std.testing.expectEqualStrings("uk_email", idx.name);
}

test "parseIndex: fulltext — @ f field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "f", "bio" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqual(IndexType.fulltext, idx.kind);
    try std.testing.expectEqualStrings("ft_bio", idx.name);
}

test "parseIndex: composite without name — @ (a, b)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "(", "a", ",", "b", ")" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_a_b", idx.name);
    try std.testing.expectEqual(@as(usize, 2), idx.fields.len);
    try std.testing.expectEqualStrings("a", idx.fields[0]);
    try std.testing.expectEqualStrings("b", idx.fields[1]);
}

test "parseIndex: full form — @ idx_name (field1, field2)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "idx_created", "(", "created_at", ")" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqual(IndexType.regular, idx.kind);
    try std.testing.expectEqualStrings("idx_created", idx.name);
    try std.testing.expectEqual(@as(usize, 1), idx.fields.len);
    try std.testing.expectEqualStrings("created_at", idx.fields[0]);
}

test "parseIndex: descending field — @ field-" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "@", "created_at-" };
    const idx = try pi.parseIndex(alloc, makeLine(&tokens, 1));
    defer freeIndexDecl(alloc, idx);
    try std.testing.expectEqualStrings("idx_created_at", idx.name);
    try std.testing.expectEqualStrings("created_at", idx.fields[0]);
    try std.testing.expectEqual(true, idx.descending[0]);
}

test "parseCompositePk: ! a, b, c" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "!", "a", ",", "b", ",", "c" };
    const idx = try pi.parseCompositePk(alloc, makeLine(&tokens, 1));
    defer {
        for (idx.fields) |f| alloc.free(f);
        alloc.free(idx.fields);
        alloc.free(idx.descending);
    }
    try std.testing.expectEqual(IndexType.primary_key, idx.kind);
    try std.testing.expectEqual(@as(usize, 3), idx.fields.len);
    try std.testing.expectEqualStrings("a", idx.fields[0]);
    try std.testing.expectEqualStrings("b", idx.fields[1]);
    try std.testing.expectEqualStrings("c", idx.fields[2]);
}
