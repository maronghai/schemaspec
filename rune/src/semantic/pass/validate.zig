const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;
const ResolvedTable = resolved_ast.ResolvedTable;
const edit_distance = @import("../../utils/edit_distance.zig");

/// Helper: validate a single FK declaration against the table and schema.
fn validateFk(ctx: *PassContext, table_names: *const std.StringHashMap(void), table_name_list: []const []const u8, table: ResolvedTable, fk: FkDecl) !void {
    // Validate FK field count matches ref_fields count
    if (fk.fields.len != fk.ref_fields.len) {
        ctx.diagnostics.push(.{
            .severity = .warning,
            .line_no = table.line_no,
            .message = try std.fmt.allocPrint(ctx.alloc, "FK field count ({d}) does not match ref_field count ({d}) in table '{s}'", .{ fk.fields.len, fk.ref_fields.len, table.name }),
        });
    }

    for (fk.fields) |fk_field| {
        var found = false;
        for (table.fields) |field| {
            if (std.mem.eql(u8, field.name, fk_field)) {
                found = true;
                break;
            }
        }
        if (!found) {
            ctx.diagnostics.push(.{
                .severity = .warning,
                .line_no = table.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "FK field '{s}' not found in table '{s}' — may be an implicit field from ultra shorthand", .{ fk_field, table.name }),
            });
        }
    }
    if (fk.ref_table.len > 0 and !table_names.contains(fk.ref_table)) {
        const suggestion = edit_distance.suggestClosest(fk.ref_table, table_name_list, 3);
        const msg = if (suggestion) |s|
            try std.fmt.allocPrint(ctx.alloc, "FK references non-existent table '{s}' in table '{s}' — did you mean '{s}'?", .{ fk.ref_table, table.name, s.match })
        else
            try std.fmt.allocPrint(ctx.alloc, "FK references non-existent table '{s}' in table '{s}'", .{ fk.ref_table, table.name });
        ctx.diagnostics.push(.{
            .severity = .warning,
            .line_no = table.line_no,
            .message = msg,
        });
    }
}

/// Semantic validation: FK reference checks, field name duplicates.
pub fn run(ctx: *PassContext) !void {
    var table_names = std.StringHashMap(void).init(ctx.alloc);
    var table_name_list = try std.ArrayList([]const u8).initCapacity(ctx.alloc, ctx.tables.items.len);
    for (ctx.tables.items) |t| {
        try table_names.put(t.name, {});
        try table_name_list.append(ctx.alloc, t.name);
    }

    for (ctx.tables.items) |table| {
        var field_names = std.StringHashMap(usize).init(ctx.alloc);
        defer field_names.deinit();
        for (table.fields, 0..) |field, fi| {
            if (std.mem.eql(u8, field.name, "...")) continue;
            if (field_names.get(field.name)) |_| {
                ctx.diagnostics.push(.{
                    .severity = .warning,
                    .line_no = field.line_no,
                    .message = try std.fmt.allocPrint(ctx.alloc, "duplicate field '{s}' in table '{s}'", .{ field.name, table.name }),
                });
            }
            try field_names.put(field.name, fi);
        }

        for (table.fks) |fk| {
            try validateFk(ctx, &table_names, table_name_list.items, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try validateFk(ctx, &table_names, table_name_list.items, table, fk);
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

test "validate: duplicate field name emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("name", .{ .simple = "s" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "duplicate field 'name'") != null);
}

test "validate: valid table produces no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });
    fields[1] = test_helpers.makeTestField("name", .{ .simple = "s" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate: FK to non-existent table emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const fks = try alloc.alloc(ast.FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "nonexistent",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "non-existent table 'nonexistent'") != null);
}

test "validate: FK to misspelled table suggests correction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const fks = try alloc.alloc(ast.FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "usrs",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = order_fields,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = user_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "did you mean 'users'") != null);
}

test "validate: FK to valid table produces no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const fks = try alloc.alloc(ast.FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = order_fields,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = user_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate: inline FK to non-existent table emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = .{
        .name = "author_id",
        .type_info = .{ .simple = "n" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = .{
            .fields = try alloc.dupe([]const u8, &.{"author_id"}),
            .ref_table = "authors",
            .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
            .actions = &.{},
            .line_no = 1,
        },
        .comment = null,
        .line_no = 1,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "posts",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "non-existent table 'authors'") != null);
}

test "validate: multiple duplicate fields emit multiple diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 3);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("email", .{ .simple = "s" });
    fields[2] = test_helpers.makeTestField("name", .{ .simple = "s" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 1), diagnostics.diagnostics.items.len);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "duplicate field 'name'") != null);
}
