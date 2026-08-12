const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;

/// Validate index names across tables: detect duplicate index names that may
/// conflict in migration output or cause issues in databases that require
/// globally unique index names (e.g. PostgreSQL).
pub fn run(ctx: *PassContext) !void {
    // Build a map of index name → (table name, line_no)
    var seen = std.StringHashMap(struct { table: []const u8, line_no: u32 }).init(ctx.alloc);
    defer seen.deinit();

    for (ctx.tables.items) |table| {
        for (table.indexes) |idx| {
            if (idx.name.len == 0) continue;
            if (seen.get(idx.name)) |existing| {
                // Skip if same table (validate_indexes handles intra-table duplicates)
                if (std.mem.eql(u8, existing.table, table.name)) continue;
                ctx.diagnostics.push(.{
                    .severity = .warning,
                    .line_no = idx.line_no,
                    .message = std.fmt.allocPrint(
                        ctx.alloc,
                        "index name '{s}' is also used in table '{s}' (line {d}) — consider renaming for clarity",
                        .{ idx.name, existing.table, existing.line_no },
                    ) catch return,
                });
            } else {
                try seen.put(idx.name, .{ .table = table.name, .line_no = @intCast(idx.line_no) });
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../../diagnostic.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeIndex(alloc: std.mem.Allocator, name: []const u8, field: []const u8, line_no: u32) !ast.IndexDecl {
    return .{
        .kind = .regular,
        .name = name,
        .fields = try alloc.dupe([]const u8, &.{field}),
        .descending = &.{false},
        .line_no = line_no,
    };
}

test "validate_index_names: cross-table duplicate emits warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, &.{test_helpers.makeTestField("name", .{ .simple = "s" })}),
        .fks = &.{},
        .indexes = try alloc.dupe(ast.IndexDecl, &.{try makeIndex(alloc, "idx_email", "name", 2)}),
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, &.{test_helpers.makeTestField("amount", .{ .simple = "m" })}),
        .fks = &.{},
        .indexes = try alloc.dupe(ast.IndexDecl, &.{try makeIndex(alloc, "idx_email", "amount", 5)}),
        .line_no = 4,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "index name 'idx_email' is also used in table 'users'") != null);
}

test "validate_index_names: same-table duplicate skipped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, &.{test_helpers.makeTestField("name", .{ .simple = "s" })}),
        .fks = &.{},
        .indexes = try alloc.dupe(ast.IndexDecl, &.{
            try makeIndex(alloc, "idx_name", "name", 2),
            try makeIndex(alloc, "idx_name", "name", 3),
        }),
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_index_names: unique names produce no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, &.{test_helpers.makeTestField("name", .{ .simple = "s" })}),
        .fks = &.{},
        .indexes = try alloc.dupe(ast.IndexDecl, &.{try makeIndex(alloc, "idx_users_name", "name", 2)}),
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, &.{test_helpers.makeTestField("amount", .{ .simple = "m" })}),
        .fks = &.{},
        .indexes = try alloc.dupe(ast.IndexDecl, &.{try makeIndex(alloc, "idx_orders_amount", "amount", 5)}),
        .line_no = 4,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
