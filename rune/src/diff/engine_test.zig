const std = @import("std");
const testing = std.testing;
const engine = @import("engine.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const ast_mod = @import("../types/ast.zig");

const ResolvedAst = resolved_ast.ResolvedAst;
const ResolvedTable = resolved_ast.ResolvedTable;
const Field = ast_mod.Field;
const TypeInfo = ast_mod.TypeInfo;

// ─── Test Helpers ──────────────────────────────────────────

fn makeField(alloc: std.mem.Allocator, name: []const u8, type_info: TypeInfo) !Field {
    return .{
        .name = try alloc.dupe(u8, name),
        .type_info = type_info,
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn makeResolvedAst(_: std.mem.Allocator, tables: []const ResolvedTable) ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

// ─── Tests ─────────────────────────────────────────────────

test "empty schemas — no differences" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old = makeResolvedAst(alloc, &.{});
    const new = makeResolvedAst(alloc, &.{});
    const result = try engine.diff(old, new, alloc);
    try testing.expect(!result.hasChanges());
}

test "added table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const old = makeResolvedAst(alloc, &.{});
    const new = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(engine.TableAction.create, result.table_diffs[0].action);
    try testing.expectEqualStrings("users", result.table_diffs[0].name);
}

test "dropped table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const old = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new = makeResolvedAst(alloc, &.{});
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    try testing.expectEqual(@as(usize, 1), result.dropped_tables.len);
    try testing.expectEqualStrings("users", result.dropped_tables[0]);
}

test "identical tables — no changes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const table = try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const old = makeResolvedAst(alloc, table);
    const new = makeResolvedAst(alloc, table);
    const result = try engine.diff(old, new, alloc);
    try testing.expect(!result.hasChanges());
}

test "added field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const new_fields = try alloc.dupe(Field, &[_]Field{ try makeField(alloc, "id", .{ .simple = "n" }), try makeField(alloc, "name", .{ .simple = "s" }) });
    const old = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(engine.FieldAction.add, result.table_diffs[0].field_diffs[0].action);
    try testing.expectEqualStrings("name", result.table_diffs[0].field_diffs[0].name);
}

test "dropped field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.dupe(Field, &[_]Field{ try makeField(alloc, "id", .{ .simple = "n" }), try makeField(alloc, "name", .{ .simple = "s" }) });
    const new_fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const old = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(engine.FieldAction.drop, result.table_diffs[0].field_diffs[0].action);
}

test "modified field — type change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "name", .{ .simple = "s" })});
    const new_fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "name", .{ .varchar_explicit = 512 })});
    const old = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(engine.FieldAction.modify, result.table_diffs[0].field_diffs[0].action);
}

test "multiple tables — mixed changes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.dupe(Field, &[_]Field{try makeField(alloc, "id", .{ .simple = "n" })});
    const old = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{
        .{ .name = "users", .comment = null, .engine = null, .fields = fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 },
        .{ .name = "posts", .comment = null, .engine = null, .fields = fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 },
    }));
    const new = makeResolvedAst(alloc, try alloc.dupe(ResolvedTable, &[_]ResolvedTable{
        .{ .name = "users", .comment = null, .engine = null, .fields = fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 },
        .{ .name = "comments", .comment = null, .engine = null, .fields = fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 },
    }));
    const result = try engine.diff(old, new, alloc);
    try testing.expect(result.hasChanges());
    // Rename detection: "posts" → "comments" (same fields, 100% overlap)
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(engine.TableAction.alter, result.table_diffs[0].action);
    try testing.expectEqualStrings("comments", result.table_diffs[0].name);
    try testing.expectEqualStrings("posts", result.table_diffs[0].rename_from.?);
    try testing.expectEqual(@as(usize, 0), result.dropped_tables.len);
}
