const std = @import("std");
const fks = @import("fks.zig");
const diff_types = @import("types.zig");
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;
const FkDiff = fks.FkDiff;
const FkAction = fks.FkAction;
const FieldDiff = fks.FieldDiff;

// ─── Test Helpers ───────────────────────────────────────────

fn makeFk(fields: []const []const u8, ref_table: []const u8, ref_fields: []const []const u8, actions: []const ast_mod.FkAction) FkDecl {
    return .{
        .fields = fields,
        .ref_table = ref_table,
        .ref_fields = ref_fields,
        .actions = actions,
        .line_no = 0,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "diffFks identical — no diffs" {
    const alloc = std.testing.allocator;
    const old = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{})};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{})};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 0), diffs.len);
}

test "diffFks added FK" {
    const alloc = std.testing.allocator;
    const old = [_]FkDecl{};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{})};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(FkAction.add, diffs[0].action);
    try std.testing.expect(diffs[0].new_fk != null);
    try std.testing.expect(diffs[0].old_fk == null);
}

test "diffFks dropped FK" {
    const alloc = std.testing.allocator;
    const old = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{})};
    const new_ = [_]FkDecl{};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(FkAction.drop, diffs[0].action);
    try std.testing.expect(diffs[0].old_fk != null);
    try std.testing.expect(diffs[0].new_fk == null);
}

test "diffFks changed FK actions — modify" {
    const alloc = std.testing.allocator;
    // Changed ref_fields from (id) to (uuid) — different structure → drop + add
    const old = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{})};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"uuid"}, &.{})};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 2), diffs.len);
    var has_add = false;
    var has_drop = false;
    for (diffs) |d| {
        if (d.action == .add) has_add = true;
        if (d.action == .drop) has_drop = true;
    }
    try std.testing.expect(has_add);
    try std.testing.expect(has_drop);
}

test "diffFks action-only change — modify" {
    const alloc = std.testing.allocator;
    // Same structure, different actions → modify (single diff, not drop+add)
    const old = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{.{ .trigger = .on_delete, .action = .cascade }})};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "user", &.{"id"}, &.{.{ .trigger = .on_delete, .action = .restrict }})};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(FkAction.modify, diffs[0].action);
    try std.testing.expect(diffs[0].old_fk != null);
    try std.testing.expect(diffs[0].new_fk != null);
}

test "diffFks add+modify action — partial match" {
    const alloc = std.testing.allocator;
    // old: FK_A(cascade) + FK_B
    // new: FK_A(restrict) + FK_C
    // Expected: modify(FK_A), drop(FK_B), add(FK_C)
    const old = [_]FkDecl{
        makeFk(&.{"user_id"}, "user", &.{"id"}, &.{.{ .trigger = .on_delete, .action = .cascade }}),
        makeFk(&.{"post_id"}, "post", &.{"id"}, &.{}),
    };
    const new_ = [_]FkDecl{
        makeFk(&.{"user_id"}, "user", &.{"id"}, &.{.{ .trigger = .on_delete, .action = .restrict }}),
        makeFk(&.{"comment_id"}, "comment", &.{"id"}, &.{}),
    };
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 3), diffs.len);
    var has_modify = false;
    var has_drop = false;
    var has_add = false;
    for (diffs) |d| {
        if (d.action == .modify) has_modify = true;
        if (d.action == .drop) has_drop = true;
        if (d.action == .add) has_add = true;
    }
    try std.testing.expect(has_modify);
    try std.testing.expect(has_drop);
    try std.testing.expect(has_add);
}

test "diffFks empty lists" {
    const alloc = std.testing.allocator;
    const old = [_]FkDecl{};
    const new_ = [_]FkDecl{};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 0), diffs.len);
}

test "diffFks multi-match bipartite" {
    const alloc = std.testing.allocator;
    // Two old FKs and two new FKs — both match → no diffs
    const old = [_]FkDecl{
        makeFk(&.{"a_id"}, "a", &.{"id"}, &.{}),
        makeFk(&.{"b_id"}, "b", &.{"id"}, &.{}),
    };
    const new_ = [_]FkDecl{
        makeFk(&.{"a_id"}, "a", &.{"id"}, &.{}),
        makeFk(&.{"b_id"}, "b", &.{"id"}, &.{}),
    };
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 0), diffs.len);
}

test "fksEqual basic" {
    const a = makeFk(&.{"user_id"}, "user", &.{"id"}, &.{});
    const b = makeFk(&.{"user_id"}, "user", &.{"id"}, &.{});
    try std.testing.expect(fks.fksEqual(a, b));
}

test "fksEqual different ref_table" {
    const a = makeFk(&.{"user_id"}, "user", &.{"id"}, &.{});
    const b = makeFk(&.{"user_id"}, "admin", &.{"id"}, &.{});
    try std.testing.expect(!fks.fksEqual(a, b));
}

test "fksEqual different fields" {
    const a = makeFk(&.{"user_id"}, "user", &.{"id"}, &.{});
    const b = makeFk(&.{"admin_id"}, "user", &.{"id"}, &.{});
    try std.testing.expect(!fks.fksEqual(a, b));
}

test "diffFks: rename-aware local field match" {
    const alloc = std.testing.allocator;
    // old FK references "uid", new FK references "user_id"
    // Field rename: uid → user_id
    const old = [_]FkDecl{makeFk(&.{"uid"}, "users", &.{"id"}, &.{})};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "users", &.{"id"}, &.{})};
    const field_diffs = [_]diff_types.FieldDiff{.{
        .name = "user_id",
        .action = .rename,
        .old_field = null,
        .new_field = null,
        .rename_from = "uid",
    }};
    const diffs = try fks.diffFks(alloc, &old, &new_, &field_diffs);
    defer alloc.free(diffs);
    // Should be modify (rename-aware match), not drop+add
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(FkAction.modify, diffs[0].action);
}

test "diffFks: rename-aware ref_field match" {
    const alloc = std.testing.allocator;
    // old FK references "users"."ref_id", new FK references "users"."uuid"
    // Field rename: ref_id → uuid
    const old = [_]FkDecl{makeFk(&.{"fk_col"}, "users", &.{"ref_id"}, &.{})};
    const new_ = [_]FkDecl{makeFk(&.{"fk_col"}, "users", &.{"uuid"}, &.{})};
    const field_diffs = [_]diff_types.FieldDiff{.{
        .name = "uuid",
        .action = .rename,
        .old_field = null,
        .new_field = null,
        .rename_from = "ref_id",
    }};
    const diffs = try fks.diffFks(alloc, &old, &new_, &field_diffs);
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 1), diffs.len);
    try std.testing.expectEqual(FkAction.modify, diffs[0].action);
}

test "diffFks: no rename match without field_diffs" {
    const alloc = std.testing.allocator;
    // Without field_diffs, renamed FK fields → drop+add
    const old = [_]FkDecl{makeFk(&.{"uid"}, "users", &.{"id"}, &.{})};
    const new_ = [_]FkDecl{makeFk(&.{"user_id"}, "users", &.{"id"}, &.{})};
    const diffs = try fks.diffFks(alloc, &old, &new_, &.{});
    defer alloc.free(diffs);
    try std.testing.expectEqual(@as(usize, 2), diffs.len);
    var has_add = false;
    var has_drop = false;
    for (diffs) |d| {
        if (d.action == .add) has_add = true;
        if (d.action == .drop) has_drop = true;
    }
    try std.testing.expect(has_add);
    try std.testing.expect(has_drop);
}
