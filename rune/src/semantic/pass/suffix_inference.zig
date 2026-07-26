const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const Field = ast.Field;
const ResolvedTable = resolved_ast.ResolvedTable;

/// Suffix-based type inference: _id → int, _on → date, _at → datetime.
pub fn run(ctx: *PassContext) !void {
    var ti_tables = try std.ArrayList(ResolvedTable).initCapacity(ctx.alloc, ctx.tables.items.len);
    for (ctx.tables.items) |table| {
        var ti_fields = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len);
        for (table.fields) |field| {
            var f = field;
            if (f.type_info == .none) {
                if (f.name.len > 3 and std.mem.endsWith(u8, f.name, "_id")) {
                    f.type_info = .{ .simple = "n" };
                } else if (f.name.len > 3 and std.mem.endsWith(u8, f.name, "_on")) {
                    f.type_info = .{ .simple = "d" };
                } else if (f.name.len > 3 and std.mem.endsWith(u8, f.name, "_at")) {
                    f.type_info = .{ .simple = "t" };
                } else {
                    f.type_info = .{ .varchar_explicit = 0 };
                }
            }
            try ti_fields.append(ctx.alloc, f);
        }
        try ti_tables.append(ctx.alloc, .{
            .name = table.name,
            .comment = table.comment,
            .engine = table.engine,
            .fields = try ti_fields.toOwnedSlice(ctx.alloc),
            .fks = table.fks,
            .indexes = table.indexes,
            .line_no = table.line_no,
        });
    }
    ctx.tables.* = ti_tables;
}

// ─── Unit Tests ─────────────────────────────────────────────

const testing = std.testing;
const diag = @import("../diagnostic.zig");

const makeTestField = @import("../test_helpers.zig").makeTestField;

fn runPassOnFields(alloc: std.mem.Allocator, fields: []const Field) !ResolvedTable {
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext{
        .alloc = alloc,
        .tables = &tables,
        .schema = null,
        .diagnostics = &diagnostics,
    };
    try run(&ctx);
    return tables.items[0];
}

test "suffix inference: _id → int" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeTestField("user_id", .none);
    const result = try runPassOnFields(alloc, fields);
    try testing.expectEqualStrings("n", result.fields[0].type_info.simple);
}

test "suffix inference: _at → datetime" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeTestField("created_at", .none);
    const result = try runPassOnFields(alloc, fields);
    try testing.expectEqualStrings("t", result.fields[0].type_info.simple);
}

test "suffix inference: _on → date" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeTestField("paid_on", .none);
    const result = try runPassOnFields(alloc, fields);
    try testing.expectEqualStrings("d", result.fields[0].type_info.simple);
}

test "suffix inference: short name → varchar" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeTestField("ab", .none);
    const result = try runPassOnFields(alloc, fields);
    try testing.expect(std.meta.activeTag(result.fields[0].type_info) == .varchar_explicit);
}

test "suffix inference: explicit type not overridden" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeTestField("point_id", .{ .varchar_explicit = 32 });
    const result = try runPassOnFields(alloc, fields);
    try testing.expect(std.meta.activeTag(result.fields[0].type_info) == .varchar_explicit);
}

test "suffix inference: multiple fields in table" {
    const alloc = testing.allocator;
    const fields = try alloc.alloc(Field, 3);
    fields[0] = makeTestField("id", .none);
    fields[1] = makeTestField("name", .none);
    fields[2] = makeTestField("created_at", .none);
    const result = try runPassOnFields(alloc, fields);
    // "id" is 2 chars → varchar fallback
    try testing.expect(std.meta.activeTag(result.fields[0].type_info) == .varchar_explicit);
    // "name" has no suffix → varchar fallback
    try testing.expect(std.meta.activeTag(result.fields[1].type_info) == .varchar_explicit);
    // "created_at" → datetime
    try testing.expectEqualStrings("t", result.fields[2].type_info.simple);
}
