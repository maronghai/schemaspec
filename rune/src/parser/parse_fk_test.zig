const std = @import("std");
const pf = @import("parse_fk.zig");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;
const FkAction = ast_mod.FkAction;
const FkActionType = ast_mod.FkActionType;

const testing = std.testing;

fn makeLine(tokens: []const []const u8, line_no: usize) tk.Line {
    return .{
        .line_type = .FK,
        .tokens = tokens,
        .raw = "",
        .trimmed = "",
        .line_no = line_no,
    };
}

test "parseFk: shorthand — field table.field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "user_id", "users.id" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    try std.testing.expectEqual(@as(usize, 1), fk.fields.len);
    try std.testing.expectEqualStrings("user_id", fk.fields[0]);
    try std.testing.expectEqualStrings("users", fk.ref_table);
    try std.testing.expectEqual(@as(usize, 1), fk.ref_fields.len);
    try std.testing.expectEqualStrings("id", fk.ref_fields[0]);
}

test "parseFk: shorthand without dot — field table" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "user_id", "users" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    try std.testing.expectEqualStrings("user_id", fk.fields[0]);
    try std.testing.expectEqualStrings("users", fk.ref_table);
    try std.testing.expectEqualStrings("id", fk.ref_fields[0]);
}

test "parseFk: ultra shorthand — > table.field" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ ">", "users.id" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    // Ultra: infers local field = users_id
    try std.testing.expectEqual(@as(usize, 1), fk.fields.len);
    try std.testing.expectEqualStrings("users_id", fk.fields[0]);
    try std.testing.expectEqualStrings("users", fk.ref_table);
    try std.testing.expectEqualStrings("id", fk.ref_fields[0]);
}

test "parseFk: ultra shorthand without dot — > table" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ ">", "users" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    try std.testing.expectEqualStrings("users_id", fk.fields[0]);
    try std.testing.expectEqualStrings("users", fk.ref_table);
    try std.testing.expectEqualStrings("id", fk.ref_fields[0]);
}

test "parseFk: with ON DELETE CASCADE (-C)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "user_id", "users.id", "-C" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    try std.testing.expectEqual(@as(usize, 1), fk.actions.len);
    try std.testing.expectEqual(.on_delete, fk.actions[0].trigger);
    try std.testing.expectEqual(.cascade, fk.actions[0].action);
}

test "parseFk: with ON DELETE SET NULL (-N) and ON UPDATE CASCADE (C)" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "user_id", "users.id", "-N", "C" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    try std.testing.expectEqual(@as(usize, 2), fk.actions.len);
    try std.testing.expectEqual(.on_delete, fk.actions[0].trigger);
    try std.testing.expectEqual(.set_null, fk.actions[0].action);
    try std.testing.expectEqual(.on_update, fk.actions[1].trigger);
    try std.testing.expectEqual(.cascade, fk.actions[1].action);
}

test "parseFk: compound FK — multiple fields" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "org_id", "project_id", "projects.org_id.project_id" };
    const fk = try pf.parseFk(alloc, makeLine(&tokens, 1));
    defer {
        alloc.free(fk.fields);
        alloc.free(fk.ref_table);
        alloc.free(fk.ref_fields);
        alloc.free(fk.actions);
    }
    // Compound: local_fields = [org_id, project_id], ref_table = projects, ref_fields = [org_id, project_id]
    try std.testing.expectEqual(@as(usize, 2), fk.fields.len);
    try std.testing.expectEqualStrings("org_id", fk.fields[0]);
    try std.testing.expectEqualStrings("project_id", fk.fields[1]);
    try std.testing.expectEqualStrings("projects", fk.ref_table);
    try std.testing.expectEqual(@as(usize, 2), fk.ref_fields.len);
    try std.testing.expectEqualStrings("org_id", fk.ref_fields[0]);
    try std.testing.expectEqualStrings("project_id", fk.ref_fields[1]);
}

test "parseFkActions: empty" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "user_id", "users.id" };
    const actions = try pf.parseFkActions(alloc, &tokens, 2);
    defer alloc.free(actions);
    try std.testing.expectEqual(@as(usize, 0), actions.len);
}
