const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;

/// Validate that FK target fields exist in the referenced table.
fn validateFkTargetFields(
    ctx: *PassContext,
    table: resolved_ast.ResolvedTable,
    fk: FkDecl,
) !void {
    if (fk.ref_table.len == 0) return;

    for (fk.ref_fields) |ref_field| {
        if (ctx.symbol_table.lookupField(fk.ref_table, ref_field) == null) {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = fk.line_no,
                .message = std.fmt.allocPrint(ctx.alloc, "FK references non-existent field '{s}' in table '{s}' (from table '{s}')", .{ ref_field, fk.ref_table, table.name }) catch return,
            });
        }
    }
}

/// Validate that all FK references point to existing fields in the target table.
/// Uses the SymbolTable built by the resolve_names pass.
pub fn run(ctx: *PassContext) !void {
    for (ctx.tables.items) |table| {
        for (table.fks) |fk| {
            try validateFkTargetFields(ctx, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try validateFkTargetFields(ctx, table, fk);
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(resolved_ast.ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector) PassContext {
    return test_helpers.makePassCtx(alloc, tables, diagnostics, .{ .init_symbol_table = true });
}

test "validate_fk_targets: non-existent field emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });

    const order_fks = try alloc.alloc(ast.FkDecl, 1);
    order_fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "user",
        .ref_fields = try alloc.dupe([]const u8, &.{"nonexistent"}),
        .actions = &.{},
        .line_no = 2,
    };

    var tables = try std.ArrayList(resolved_ast.ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = order_fields,
        .fks = order_fks,
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = user_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    var found_error = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "non-existent field") != null) {
            found_error = true;
            break;
        }
    }
    try testing.expect(found_error);
}

test "validate_fk_targets: valid FK produces no error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n++" });

    const order_fks = try alloc.alloc(ast.FkDecl, 1);
    order_fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "user",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 2,
    };

    var tables = try std.ArrayList(resolved_ast.ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "order",
        .comment = null,
        .engine = null,
        .fields = order_fields,
        .fks = order_fks,
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "user",
        .comment = null,
        .engine = null,
        .fields = user_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
