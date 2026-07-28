const std = @import("std");
const idx = @import("indexes.zig");
const ast_mod = @import("../types/ast.zig");
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
const IndexAction = idx.IndexAction;

// ─── Test Helpers ───────────────────────────────────────────

fn makeIdx(kind: IndexType, name: []const u8, fields: []const []const u8) IndexDecl {
    return .{
        .kind = kind,
        .name = name,
        .fields = fields,
        .descending = &.{},
        .line_no = 0,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "diffIndexes identical — no diffs" {
    const alloc = std.testing.allocator;
    const old = [_]IndexDecl{makeIdx(.regular, "idx_a", &.{ "a", "b" })};
    const new_ = [_]IndexDecl{makeIdx(.regular, "idx_a", &.{ "a", "b" })};
    const diffs = try idx.diffIndexes(alloc, &old, &new_);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 0), diffs.len);
}

test "diffIndexes added index" {
    const alloc = std.testing.allocator;
    const old = [_]IndexDecl{};
    const new_ = [_]IndexDecl{makeIdx(.unique, "uk_email", &.{"email"})};
    const diffs = try idx.diffIndexes(alloc, &old, &new_);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(IndexAction.add, diffs[0].action);
    try std.testing.expectEqualStrings("uk_email", diffs[0].name);
}

test "diffIndexes dropped index" {
    const alloc = std.testing.allocator;
    const old = [_]IndexDecl{makeIdx(.regular, "idx_a", &.{"a"})};
    const new_ = [_]IndexDecl{};
    const diffs = try idx.diffIndexes(alloc, &old, &new_);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(IndexAction.drop, diffs[0].action);
}

test "diffIndexes modified index (kind change)" {
    const alloc = std.testing.allocator;
    const old = [_]IndexDecl{makeIdx(.regular, "idx_a", &.{"a"})};
    const new_ = [_]IndexDecl{makeIdx(.unique, "idx_a", &.{"a"})};
    const diffs = try idx.diffIndexes(alloc, &old, &new_);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(IndexAction.modify, diffs[0].action);
}

test "diffIndexes modified index (field change)" {
    const alloc = std.testing.allocator;
    const old = [_]IndexDecl{makeIdx(.regular, "idx_ab", &.{ "a", "b" })};
    const new_ = [_]IndexDecl{makeIdx(.regular, "idx_ab", &.{ "a", "c" })};
    const diffs = try idx.diffIndexes(alloc, &old, &new_);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(IndexAction.modify, diffs[0].action);
}

test "indexesEqual same kind and fields" {
    const a = makeIdx(.unique, "uk", &.{ "a", "b" });
    const b = makeIdx(.unique, "uk", &.{ "a", "b" });
    try std.testing.expect(idx.indexesEqual(a, b));
}

test "indexesEqual different kind" {
    const a = makeIdx(.regular, "idx", &.{"a"});
    const b = makeIdx(.unique, "idx", &.{"a"});
    try std.testing.expect(!idx.indexesEqual(a, b));
}

test "indexesEqual different field count" {
    const a = makeIdx(.regular, "idx", &.{"a"});
    const b = makeIdx(.regular, "idx", &.{ "a", "b" });
    try std.testing.expect(!idx.indexesEqual(a, b));
}

test "indexesEqual same fields but different descending" {
    var desc_a = [_]bool{ true, false };
    var desc_b = [_]bool{ false, false };
    const a = IndexDecl{
        .kind = .regular,
        .name = "idx",
        .fields = &.{ "a", "b" },
        .descending = &desc_a,
        .line_no = 0,
    };
    const b = IndexDecl{
        .kind = .regular,
        .name = "idx",
        .fields = &.{ "a", "b" },
        .descending = &desc_b,
        .line_no = 0,
    };
    try std.testing.expect(!idx.indexesEqual(a, b));
}

test "indexesEqual same fields and same descending" {
    var desc_a = [_]bool{ true, false };
    var desc_b = [_]bool{ true, false };
    const a = IndexDecl{
        .kind = .regular,
        .name = "idx",
        .fields = &.{ "a", "b" },
        .descending = &desc_a,
        .line_no = 0,
    };
    const b = IndexDecl{
        .kind = .regular,
        .name = "idx",
        .fields = &.{ "a", "b" },
        .descending = &desc_b,
        .line_no = 0,
    };
    try std.testing.expect(idx.indexesEqual(a, b));
}
