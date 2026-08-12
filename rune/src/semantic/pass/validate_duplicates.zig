const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;

/// Validate that no two tables share the same name.
/// Uses the SymbolTable built by the resolve_names pass.
pub fn run(ctx: *PassContext) !void {
    var seen_tables = std.StringHashMap(usize).init(ctx.alloc);
    for (ctx.tables.items, 0..) |table, i| {
        if (seen_tables.get(table.name)) |first_idx| {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = table.line_no,
                .message = std.fmt.allocPrint(ctx.alloc, "duplicate table name '{s}' (first declared at table #{d})", .{ table.name, first_idx + 1 }) catch return,
            });
        } else {
            try seen_tables.put(table.name, i);
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../../diagnostic.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector) PassContext {
    return test_helpers.makePassCtx(alloc, tables, diagnostics, .{ .init_symbol_table = true });
}

test "validate_duplicates: duplicate table names emit diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const a_fields = try alloc.alloc(ast.Field, 1);
    a_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const b_fields = try alloc.alloc(ast.Field, 1);
    b_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = a_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = b_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    var found_duplicate = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "duplicate table name") != null) {
            found_duplicate = true;
            break;
        }
    }
    try testing.expect(found_duplicate);
}

test "validate_duplicates: unique table names produce no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const a_fields = try alloc.alloc(ast.Field, 1);
    a_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = a_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
