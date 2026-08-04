const std = @import("std");
const diff_mod = @import("engine.zig");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const diff = diff_mod.diff;
const TableAction = diff_mod.TableAction;
const FieldAction = diff_mod.FieldAction;
const IndexAction = diff_mod.IndexAction;
const ViewAction = diff_mod.ViewAction;
const TypeInfo = ast_mod.TypeInfo;
const Field = ast_mod.Field;
const IndexDecl = ast_mod.IndexDecl;

const testing = std.testing;

fn freeSchemaDiff(alloc: std.mem.Allocator, d: diff_mod.SchemaDiff) void {
    alloc.free(d.dropped_tables);
    alloc.free(d.view_diffs);
    for (d.table_diffs) |td| {
        alloc.free(td.field_diffs);
        alloc.free(td.index_diffs);
        alloc.free(td.fk_diffs);
    }
    alloc.free(d.table_diffs);
}

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

fn makeResolvedAst(_: std.mem.Allocator, tables: []const resolved_ast.ResolvedTable) resolved_ast.ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

test "diff: table engine change detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = null,
        .engine = "InnoDB",
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = null,
        .engine = "MyISAM",
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expect(result.table_diffs[0].metadata_diff != null);
    try testing.expectEqualStrings("InnoDB", result.table_diffs[0].metadata_diff.?.old_engine.?);
    try testing.expectEqualStrings("MyISAM", result.table_diffs[0].metadata_diff.?.new_engine.?);
}

test "diff: no metadata change produces null metadata_diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "same",
        .engine = "InnoDB",
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "same",
        .engine = "InnoDB",
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
}

test "diff: combined field and metadata change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    new_fields[1] = try makeField(alloc, "name", .{ .simple = "s" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "old",
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "new",
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expect(result.table_diffs[0].metadata_diff != null);
}

test "diff: no changes produces empty diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const t = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const old_ast = makeResolvedAst(alloc, t);
    const new_ast = makeResolvedAst(alloc, t);

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), result.dropped_tables.len);
}

test "diff: new table detected as create" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_ast = makeResolvedAst(alloc, &.{});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_ast = makeResolvedAst(alloc, new_table);

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(TableAction.create, result.table_diffs[0].action);
    try testing.expectEqualStrings("user", result.table_diffs[0].name);
}

test "diff: dropped table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const old_ast = makeResolvedAst(alloc, old_table);
    const new_ast = makeResolvedAst(alloc, &.{});

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.dropped_tables.len);
    try testing.expectEqualStrings("user", result.dropped_tables[0]);
}

test "diff: added field detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    new_fields[1] = try makeField(alloc, "name", .{ .varchar_explicit = 32 });

    const old_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(TableAction.alter, result.table_diffs[0].action);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(FieldAction.add, result.table_diffs[0].field_diffs[0].action);
    try testing.expectEqualStrings("name", result.table_diffs[0].field_diffs[0].name);
}

test "diff: renamed field detected by signature match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 2);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    old_fields[1] = try makeField(alloc, "name", .{ .varchar_explicit = 32 });

    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    new_fields[1] = try makeField(alloc, "full_name", .{ .varchar_explicit = 32 });

    const old_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(FieldAction.rename, result.table_diffs[0].field_diffs[0].action);
    try testing.expectEqualStrings("full_name", result.table_diffs[0].field_diffs[0].name);
    try testing.expect(result.table_diffs[0].field_diffs[0].rename_from != null);
    try testing.expectEqualStrings("name", result.table_diffs[0].field_diffs[0].rename_from.?);
}

test "diff: two empty schemas produce no diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old = makeResolvedAst(alloc, &.{});
    const new = makeResolvedAst(alloc, &.{});

    const result = try diff(old, new, alloc);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), result.dropped_tables.len);
}

test "diff: table created and dropped simultaneously" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const new_fields = try alloc.alloc(Field, 1);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "accounts",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.dropped_tables.len);
    try testing.expectEqualStrings("users", result.dropped_tables[0]);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(TableAction.create, result.table_diffs[0].action);
    try testing.expectEqualStrings("accounts", result.table_diffs[0].name);
}

test "diff: field type change detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = try makeField(alloc, "count", .{ .simple = "n" });

    const new_fields = try alloc.alloc(Field, 1);
    new_fields[0] = try makeField(alloc, "count", .{ .simple = "N" });

    const old_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "stats",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));
    const new_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "stats",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}));

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].field_diffs.len);
    try testing.expectEqual(FieldAction.modify, result.table_diffs[0].field_diffs[0].action);
}

test "diff: index added and dropped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 2);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    fields[1] = try makeField(alloc, "email", .{ .simple = "s" });

    const old_idx = try alloc.alloc(IndexDecl, 1);
    old_idx[0] = .{ .kind = .unique, .name = "uk_email", .fields = &.{"email"}, .descending = &.{false}, .line_no = 1 };

    const new_idx = try alloc.alloc(IndexDecl, 1);
    new_idx[0] = .{ .kind = .regular, .name = "idx_email", .fields = &.{"email"}, .descending = &.{false}, .line_no = 1 };

    const old_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = old_idx,
        .line_no = 1,
    }}));
    const new_ast = makeResolvedAst(alloc, try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = new_idx,
        .line_no = 1,
    }}));

    const result = try diff(old_ast, new_ast, alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    // unique→regular on same column = drop + add (2 diffs), not modify
    try testing.expectEqual(@as(usize, 2), result.table_diffs[0].index_diffs.len);
}

test "diff: no changes on identical tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 2);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    fields[1] = try makeField(alloc, "name", .{ .simple = "s" });

    const t1 = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const t2 = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, t1), makeResolvedAst(alloc, t2), alloc);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), result.dropped_tables.len);
}

test "diff: field added and dropped simultaneously" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 2);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    old_fields[1] = try makeField(alloc, "old_col", .{ .simple = "s" });

    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    new_fields[1] = try makeField(alloc, "new_col", .{ .simple = "n" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = old_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = new_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 2), result.table_diffs[0].field_diffs.len);
}

test "diff: FK change detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const fk1 = try alloc.dupe(ast_mod.FkDecl, &.{.{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{.{ .trigger = .on_delete, .action = .cascade }},
        .line_no = 1,
    }});
    const fk2 = try alloc.dupe(ast_mod.FkDecl, &.{.{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{.{ .trigger = .on_delete, .action = .set_null }},
        .line_no = 1,
    }});

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = fk1,
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = fk2,
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(@as(usize, 1), result.table_diffs[0].fk_diffs.len);
}

test "diff: table comment change detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = try makeField(alloc, "id", .{ .simple = "n" });

    const old_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "old comment",
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});
    const new_table = try alloc.dupe(resolved_ast.ResolvedTable, &.{.{
        .name = "t",
        .comment = "new comment",
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }});

    const result = try diff(makeResolvedAst(alloc, old_table), makeResolvedAst(alloc, new_table), alloc);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expect(result.table_diffs[0].metadata_diff != null);
    try testing.expectEqualStrings("old comment", result.table_diffs[0].metadata_diff.?.old_comment.?);
    try testing.expectEqualStrings("new comment", result.table_diffs[0].metadata_diff.?.new_comment.?);
}

// ─── Tests moved from diff/engine.zig ───────────────────────────

test "engine diff: dropping a table produces a dropped_tables entry" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    const old_tables = try alloc.alloc(resolved_ast.ResolvedTable, 1);
    old_tables[0] = .{ .name = "users", .comment = null, .engine = null, .fields = old_fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 };

    const new_tables = try alloc.alloc(resolved_ast.ResolvedTable, 0);

    const old_ast = makeResolvedAst(alloc, old_tables);
    const new_ast = makeResolvedAst(alloc, new_tables);
    const schema_diff = try diff(old_ast, new_ast, alloc);

    try testing.expectEqual(@as(usize, 1), schema_diff.dropped_tables.len);
    try testing.expectEqualStrings("users", schema_diff.dropped_tables[0]);
}

test "engine diff: modifying a field produces a modify action" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_fields = try alloc.alloc(Field, 2);
    old_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    old_fields[1] = try makeField(alloc, "name", .{ .simple = "s" });
    const old_tables = try alloc.alloc(resolved_ast.ResolvedTable, 1);
    old_tables[0] = .{ .name = "users", .comment = null, .engine = null, .fields = old_fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 };

    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = try makeField(alloc, "id", .{ .simple = "n" });
    new_fields[1] = try makeField(alloc, "name", .{ .simple = "t" }); // changed from s to t
    const new_tables = try alloc.alloc(resolved_ast.ResolvedTable, 1);
    new_tables[0] = .{ .name = "users", .comment = null, .engine = null, .fields = new_fields, .fks = &.{}, .indexes = &.{}, .line_no = 1 };

    const old_ast = makeResolvedAst(alloc, old_tables);
    const new_ast = makeResolvedAst(alloc, new_tables);
    const schema_diff = try diff(old_ast, new_ast, alloc);

    try testing.expectEqual(@as(usize, 1), schema_diff.table_diffs.len);
    try testing.expectEqual(TableAction.alter, schema_diff.table_diffs[0].action);
    try testing.expectEqual(@as(usize, 1), schema_diff.table_diffs[0].field_diffs.len);
    try testing.expectEqual(FieldAction.modify, schema_diff.table_diffs[0].field_diffs[0].action);
}

test "engine diff: view creation produces a view_diffs entry" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_tables = try alloc.alloc(resolved_ast.ResolvedTable, 0);
    const new_views = try alloc.alloc(ast_mod.View, 1);
    new_views[0] = .{ .name = "user_view", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };

    const old_ast = makeResolvedAst(alloc, old_tables);
    var new_ast = makeResolvedAst(alloc, old_tables);
    new_ast.views = new_views;

    const schema_diff = try diff(old_ast, new_ast, alloc);

    try testing.expectEqual(@as(usize, 1), schema_diff.view_diffs.len);
    try testing.expectEqual(ViewAction.create, schema_diff.view_diffs[0].action);
    try testing.expectEqualStrings("user_view", schema_diff.view_diffs[0].name);
}

test "engine diff: identical views produce no view_diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const views = try alloc.alloc(ast_mod.View, 1);
    views[0] = .{ .name = "user_view", .query = "SELECT id FROM users", .comment = null, .line_no = 1 };

    const old_ast = makeResolvedAst(alloc, &.{});
    var new_ast = makeResolvedAst(alloc, &.{});
    new_ast.views = views;

    var old_ast_with_views = old_ast;
    old_ast_with_views.views = views;

    const schema_diff = try diff(old_ast_with_views, new_ast, alloc);

    try testing.expectEqual(@as(usize, 0), schema_diff.view_diffs.len);
}
