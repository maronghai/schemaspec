const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;
const ResolvedTable = resolved_ast.ResolvedTable;

/// Helper: validate a single FK declaration against the table and schema.
fn validateFk(ctx: *PassContext, table_names: *const std.StringHashMap(void), table: ResolvedTable, fk: FkDecl) !void {
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
        ctx.diagnostics.push(.{
            .severity = .warning,
            .line_no = table.line_no,
            .message = try std.fmt.allocPrint(ctx.alloc, "FK references non-existent table '{s}' in table '{s}'", .{ fk.ref_table, table.name }),
        });
    }
}

/// Semantic validation: FK reference checks, field name duplicates.
pub fn run(ctx: *PassContext) !void {
    var table_names = std.StringHashMap(void).init(ctx.alloc);
    for (ctx.tables.items) |t| {
        try table_names.put(t.name, {});
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
            try validateFk(ctx, &table_names, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try validateFk(ctx, &table_names, table, fk);
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector) PassContext {
    return .{
        .alloc = alloc,
        .tables = tables,
        .schema = null,
        .diagnostics = diagnostics,
    };
}

test "validate: duplicate field name emits diagnostic" {
    const alloc = testing.allocator;
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
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "duplicate field 'name'") != null);
}

test "validate: valid table produces no diagnostics" {
    const alloc = testing.allocator;
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
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate: FK to non-existent table emits diagnostic" {
    const alloc = testing.allocator;
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
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "non-existent table 'nonexistent'") != null);
}
