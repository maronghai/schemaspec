const std = @import("std");
const rename = @import("../diff/rename.zig");
const diff_types = @import("../diff/types.zig");

// ─── applyRenames Tests ─────────────────────────────────────

test "applyRenames: no renames returns original fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &.{ "a", "b", "c" };
    const field_diffs = &.{diff_types.FieldDiff{
        .name = "x",
        .action = .add,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    }};

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("a", result[0]);
    try std.testing.expectEqualStrings("b", result[1]);
    try std.testing.expectEqualStrings("c", result[2]);
}

test "applyRenames: single rename" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &.{ "old_name", "b" };
    const field_diffs = &.{diff_types.FieldDiff{
        .name = "new_name",
        .action = .rename,
        .old_field = null,
        .new_field = null,
        .rename_from = "old_name",
    }};

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("new_name", result[0]);
    try std.testing.expectEqualStrings("b", result[1]);
}

test "applyRenames: multiple renames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &.{ "x", "y", "z" };
    const field_diffs = &.{
        diff_types.FieldDiff{
            .name = "a",
            .action = .rename,
            .old_field = null,
            .new_field = null,
            .rename_from = "x",
        },
        diff_types.FieldDiff{
            .name = "b",
            .action = .rename,
            .old_field = null,
            .new_field = null,
            .rename_from = "z",
        },
    };

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("a", result[0]);
    try std.testing.expectEqualStrings("y", result[1]);
    try std.testing.expectEqualStrings("b", result[2]);
}

test "applyRenames: empty fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &[_][]const u8{};
    const field_diffs = &[_]diff_types.FieldDiff{};

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "applyRenames: rename not matching any field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &.{ "a", "b" };
    const field_diffs = &.{diff_types.FieldDiff{
        .name = "c",
        .action = .rename,
        .old_field = null,
        .new_field = null,
        .rename_from = "nonexistent",
    }};

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("a", result[0]);
    try std.testing.expectEqualStrings("b", result[1]);
}

test "applyRenames: non-rename actions ignored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = &.{ "a", "b" };
    const field_diffs = &.{
        diff_types.FieldDiff{
            .name = "a",
            .action = .drop,
            .old_field = null,
            .new_field = null,
            .rename_from = null,
        },
        diff_types.FieldDiff{
            .name = "a",
            .action = .modify,
            .old_field = null,
            .new_field = null,
            .rename_from = null,
        },
    };

    const result = try rename.applyRenames(alloc, fields, field_diffs);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("a", result[0]);
    try std.testing.expectEqualStrings("b", result[1]);
}
