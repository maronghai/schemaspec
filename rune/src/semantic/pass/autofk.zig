const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const Field = ast.Field;
const FkDecl = ast.FkDecl;
const IndexDecl = ast.IndexDecl;
const ResolvedTable = resolved_ast.ResolvedTable;

/// Auto FK inference: _id suffix → foreign key to matching table.
pub fn run(ctx: *PassContext) !void {
    if (ctx.schema == null or !ctx.schema.?.autofk) return;

    var table_map = std.StringHashMap(void).init(ctx.alloc);
    for (ctx.tables.items) |t| {
        try table_map.put(t.name, {});
    }

    var new_tables = try std.ArrayList(ResolvedTable).initCapacity(ctx.alloc, ctx.tables.items.len);
    for (ctx.tables.items) |table| {
        var new_fields = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len);
        var new_indexes = try std.ArrayList(IndexDecl).initCapacity(ctx.alloc, table.indexes.len + 4);
        for (table.indexes) |idx| {
            try new_indexes.append(ctx.alloc, idx);
        }
        for (table.fields) |field| {
            var f = field;
            if (f.fk == null and f.name.len > 3 and std.mem.endsWith(u8, f.name, "_id")) {
                const prefix = f.name[0 .. f.name.len - 3];
                if (prefix.len > 0 and table_map.contains(prefix)) {
                    var local_fields = try ctx.alloc.alloc([]const u8, 1);
                    local_fields[0] = f.name;
                    var ref_fields = try ctx.alloc.alloc([]const u8, 1);
                    ref_fields[0] = "id";
                    f.fk = FkDecl{
                        .fields = local_fields,
                        .ref_table = try ctx.alloc.dupe(u8, prefix),
                        .ref_fields = ref_fields,
                        .actions = &.{},
                        .line_no = f.line_no,
                    };
                    var already_indexed = false;
                    for (table.indexes) |idx| {
                        for (idx.fields) |idx_f| {
                            if (std.mem.eql(u8, idx_f, f.name)) {
                                already_indexed = true;
                                break;
                            }
                        }
                        if (already_indexed) break;
                    }
                    if (!already_indexed) {
                        var idx_fields = try ctx.alloc.alloc([]const u8, 1);
                        idx_fields[0] = f.name;
                        const idx_name = try std.fmt.allocPrint(ctx.alloc, "idx_{s}", .{f.name});
                        try new_indexes.append(ctx.alloc, .{
                            .kind = .regular,
                            .name = idx_name,
                            .fields = idx_fields,
                            .descending = &.{false},
                            .line_no = f.line_no,
                        });
                    }
                }
            }
            try new_fields.append(ctx.alloc, f);
        }
        try new_tables.append(ctx.alloc, .{
            .name = table.name,
            .comment = table.comment,
            .engine = table.engine,
            .fields = try new_fields.toOwnedSlice(ctx.alloc),
            .fks = table.fks,
            .indexes = try new_indexes.toOwnedSlice(ctx.alloc),
            .line_no = table.line_no,
        });
    }
    ctx.tables.* = new_tables;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector, schema: ?ast.Schema) PassContext {
    return .{
        .alloc = alloc,
        .tables = tables,
        .schema = schema,
        .diagnostics = diagnostics,
    };
}

test "autofk: _id suffix triggers FK inference" {
    const alloc = testing.allocator;

    const user_fields = try alloc.alloc(Field, 2);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });
    user_fields[1] = test_helpers.makeTestField("name", .{ .simple = "s" });

    const order_fields = try alloc.alloc(Field, 2);
    order_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });
    order_fields[1] = test_helpers.makeTestField("user_id", .none);

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = user_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = order_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics, .{
        .name = "demo",
        .charset = null,
        .autofk = true,
        .custom_types = &.{},
        .line_no = 1,
    });
    try run(&ctx);

    // user_id field should now have an FK
    const order = ctx.tables.items[1];
    const uid_field = order.fields[1];
    try testing.expect(uid_field.fk != null);
    try testing.expectEqualStrings("user", uid_field.fk.?.ref_table);
}

test "autofk: no suffix means no FK" {
    const alloc = testing.allocator;

    const fields = try alloc.alloc(Field, 2);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });
    fields[1] = test_helpers.makeTestField("tag", .{ .simple = "s" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "item",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics, .{
        .name = "demo",
        .charset = null,
        .autofk = true,
        .custom_types = &.{},
        .line_no = 1,
    });
    try run(&ctx);

    // No FK should be added
    const item = ctx.tables.items[0];
    try testing.expect(item.fields[1].fk == null);
}

test "autofk: disabled schema skips inference" {
    const alloc = testing.allocator;

    const fields = try alloc.alloc(Field, 2);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });
    fields[1] = test_helpers.makeTestField("user_id", .none);

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics, .{
        .name = "demo",
        .charset = null,
        .autofk = false,
        .custom_types = &.{},
        .line_no = 1,
    });
    try run(&ctx);

    // autofk disabled → no FK
    try testing.expect(ctx.tables.items[0].fields[1].fk == null);
}
