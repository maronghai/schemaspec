const std = @import("std");
const tmpl = @import("template.zig");
const ast_mod = @import("../types/ast.zig");
const Field = ast_mod.Field;

const testing = std.testing;
const test_helpers = struct {
    const makeTestField = @import("test_helpers.zig").makeTestField;
    const makeTestAst = @import("test_helpers.zig").makeTestAst;
};

test "template application: fields merged in order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tmpl_fields = try alloc.alloc(Field, 3);
    tmpl_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });
    tmpl_fields[1] = test_helpers.makeTestField("...", .none);
    tmpl_fields[2] = test_helpers.makeTestField("status", .{ .simple = "1" });

    const template = ast_mod.Template{
        .name = "base",
        .parents = &.{},
        .fields = tmpl_fields,
        .slot_index = 1,
        .line_no = 1,
    };

    const table_fields = try alloc.alloc(Field, 1);
    table_fields[0] = test_helpers.makeTestField("name", .{ .varchar_explicit = 32 });

    const table = ast_mod.Table{
        .name = "user",
        .template_ref = "base",
        .comment = null,
        .engine = null,
        .fields = table_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    const ast = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{table}), try alloc.dupe(ast_mod.Template, &.{template}));
    const tables = try tmpl.resolveAndApply(alloc, ast);

    try testing.expectEqual(@as(usize, 3), tables[0].fields.len);
    try testing.expectEqualStrings("id", tables[0].fields[0].name);
    try testing.expectEqualStrings("name", tables[0].fields[1].name);
    try testing.expectEqualStrings("status", tables[0].fields[2].name);
}

test "template: 3-level inheritance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const gp_fields = try alloc.alloc(Field, 1);
    gp_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });
    const gp_tmpl = ast_mod.Template{ .name = "gp", .parents = &.{}, .fields = gp_fields, .slot_index = null, .line_no = 1 };

    const p_fields = try alloc.alloc(Field, 1);
    p_fields[0] = test_helpers.makeTestField("status", .{ .simple = "1" });
    const p_tmpl = ast_mod.Template{ .name = "p", .parents = &.{"gp"}, .fields = p_fields, .slot_index = null, .line_no = 1 };

    const c_fields = try alloc.alloc(Field, 1);
    c_fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    const c_tmpl = ast_mod.Template{ .name = "c", .parents = &.{"p"}, .fields = c_fields, .slot_index = null, .line_no = 1 };

    const table = ast_mod.Table{
        .name = "t",
        .template_ref = "c",
        .comment = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    const ast = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{table}), try alloc.dupe(ast_mod.Template, &.{ gp_tmpl, p_tmpl, c_tmpl }));
    const tables = try tmpl.resolveAndApply(alloc, ast);

    try testing.expectEqual(@as(usize, 3), tables[0].fields.len);
    try testing.expectEqualStrings("id", tables[0].fields[0].name);
    try testing.expectEqualStrings("status", tables[0].fields[1].name);
    try testing.expectEqualStrings("name", tables[0].fields[2].name);
}

test "template: multiple mixins" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const m1_fields = try alloc.alloc(Field, 1);
    m1_fields[0] = test_helpers.makeTestField("created_at", .none);
    const m1 = ast_mod.Template{ .name = "timestamps", .parents = &.{}, .fields = m1_fields, .slot_index = null, .line_no = 1 };

    const m2_fields = try alloc.alloc(Field, 1);
    m2_fields[0] = test_helpers.makeTestField("deleted_at", .none);
    const m2 = ast_mod.Template{ .name = "softdel", .parents = &.{}, .fields = m2_fields, .slot_index = null, .line_no = 1 };

    const audit_fields = try alloc.alloc(Field, 0);
    const audit = ast_mod.Template{ .name = "audit", .parents = &.{ "timestamps", "softdel" }, .fields = audit_fields, .slot_index = null, .line_no = 1 };

    const table = ast_mod.Table{
        .name = "t",
        .template_ref = "audit",
        .comment = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    const ast = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{table}), try alloc.dupe(ast_mod.Template, &.{ m1, m2, audit }));
    const tables = try tmpl.resolveAndApply(alloc, ast);

    try testing.expectEqual(@as(usize, 2), tables[0].fields.len);
    try testing.expectEqualStrings("created_at", tables[0].fields[0].name);
    try testing.expectEqualStrings("deleted_at", tables[0].fields[1].name);
}

test "template: child field type overrides parent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parent_fields = try alloc.alloc(Field, 1);
    parent_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });
    const parent = ast_mod.Template{ .name = "base", .parents = &.{}, .fields = parent_fields, .slot_index = null, .line_no = 1 };

    const child_fields = try alloc.alloc(Field, 1);
    child_fields[0] = test_helpers.makeTestField("id", .{ .simple = "N" });
    const child = ast_mod.Template{ .name = "big_base", .parents = &.{"base"}, .fields = child_fields, .slot_index = null, .line_no = 1 };

    const table = ast_mod.Table{
        .name = "t",
        .template_ref = "big_base",
        .comment = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    const ast = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{table}), try alloc.dupe(ast_mod.Template, &.{ parent, child }));
    const tables = try tmpl.resolveAndApply(alloc, ast);

    try testing.expectEqual(@as(usize, 1), tables[0].fields.len);
    try testing.expectEqualStrings("N", tables[0].fields[0].type_info.simple);
}
