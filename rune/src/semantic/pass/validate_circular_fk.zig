const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;
const ResolvedTable = resolved_ast.ResolvedTable;

const VisitStatus = enum { visiting, visited };

/// DFS-based cycle detection in the FK dependency graph.
fn detectCycle(
    ctx: *PassContext,
    fk_graph: *const std.StringHashMap(std.ArrayList([]const u8)),
    visited: *std.StringHashMap(VisitStatus),
    stack: *std.ArrayList([]const u8),
    node: []const u8,
) !void {
    try visited.put(node, .visiting);
    try stack.append(ctx.alloc, node);

    if (fk_graph.get(node)) |refs| {
        for (refs.items) |ref_table| {
            if (visited.get(ref_table)) |status| {
                if (status == .visiting) {
                    var cycle_path = std.fmt.allocPrint(ctx.alloc, "{s}", .{ref_table}) catch return;
                    var i = stack.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (std.mem.eql(u8, stack.items[i], ref_table)) break;
                        cycle_path = std.fmt.allocPrint(ctx.alloc, "{s} -> {s}", .{ stack.items[i], cycle_path }) catch return;
                    }
                    ctx.diagnostics.push(.{
                        .severity = .warning,
                        .line_no = 0,
                        .message = std.fmt.allocPrint(ctx.alloc, "circular FK dependency detected: {s}", .{cycle_path}) catch return,
                    });
                }
            } else {
                try detectCycle(ctx, fk_graph, visited, stack, ref_table);
            }
        }
    }

    _ = stack.pop();
    try visited.put(node, .visited);
}

/// Validate circular FK chains and self-referencing FK field count mismatches.
pub fn run(ctx: *PassContext) !void {
    // Build FK dependency graph for cycle detection
    var fk_graph = std.StringHashMap(std.ArrayList([]const u8)).init(ctx.alloc);
    defer {
        var git = fk_graph.iterator();
        while (git.next()) |entry| {
            entry.value_ptr.deinit(ctx.alloc);
        }
        fk_graph.deinit();
    }

    for (ctx.tables.items) |table| {
        var refs = try std.ArrayList([]const u8).initCapacity(ctx.alloc, 4);
        for (table.fks) |fk| {
            if (fk.ref_table.len > 0) {
                try refs.append(ctx.alloc, fk.ref_table);
            }
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                if (fk.ref_table.len > 0) {
                    try refs.append(ctx.alloc, fk.ref_table);
                }
            }
        }
        try fk_graph.put(table.name, refs);
    }

    // DFS cycle detection
    var visited = std.StringHashMap(VisitStatus).init(ctx.alloc);
    defer visited.deinit();

    var cycle_stack = try std.ArrayList([]const u8).initCapacity(ctx.alloc, 8);
    defer cycle_stack.deinit(ctx.alloc);

    for (ctx.tables.items) |table| {
        if (visited.contains(table.name)) continue;
        try detectCycle(ctx, &fk_graph, &visited, &cycle_stack, table.name);
    }

    // Validate self-referencing FK field count
    for (ctx.tables.items) |table| {
        for (table.fks) |fk| {
            validateSelfRefFk(ctx, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                validateSelfRefFk(ctx, table, fk);
            }
        }
    }
}

fn validateSelfRefFk(ctx: *PassContext, table: ResolvedTable, fk: FkDecl) void {
    if (!std.mem.eql(u8, fk.ref_table, table.name)) return;
    if (fk.fields.len != fk.ref_fields.len) {
        ctx.diagnostics.push(.{
            .severity = .@"error",
            .line_no = fk.line_no,
            .message = std.fmt.allocPrint(ctx.alloc, "self-referencing FK in table '{s}' has mismatched field count: {d} local vs {d} referenced", .{ table.name, fk.fields.len, fk.ref_fields.len }) catch return,
        });
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector) PassContext {
    return test_helpers.makePassCtx(alloc, tables, diagnostics, .{ .init_symbol_table = true });
}

test "validate_circular_fk: circular FK emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const a_fields = try alloc.alloc(ast.Field, 1);
    a_fields[0] = test_helpers.makeTestField("b_id", .{ .simple = "n" });

    const b_fields = try alloc.alloc(ast.Field, 1);
    b_fields[0] = test_helpers.makeTestField("a_id", .{ .simple = "n" });

    const a_fks = try alloc.alloc(ast.FkDecl, 1);
    a_fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"b_id"}),
        .ref_table = "b",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 2,
    };

    const b_fks = try alloc.alloc(ast.FkDecl, 1);
    b_fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"a_id"}),
        .ref_table = "a",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 6,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "a",
        .comment = null,
        .engine = null,
        .fields = a_fields,
        .fks = a_fks,
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "b",
        .comment = null,
        .engine = null,
        .fields = b_fields,
        .fks = b_fks,
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    var found_circular = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "circular") != null) {
            found_circular = true;
            break;
        }
    }
    try testing.expect(found_circular);
}

test "validate_circular_fk: non-circular FK produces no circular diagnostic" {
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

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
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

    for (diagnostics.diagnostics.items) |d| {
        try testing.expect(std.mem.indexOf(u8, d.message, "circular") == null);
    }
}

test "validate_circular_fk: self-referencing FK with mismatched fields emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("parent_id", .{ .simple = "n" });
    fields[1] = test_helpers.makeTestField("name", .{ .simple = "s" });

    const fks = try alloc.alloc(ast.FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{ "parent_id", "name" }),
        .ref_table = "categories",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 2,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "categories",
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

    var found_mismatch = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "mismatched field count") != null) {
            found_mismatch = true;
            break;
        }
    }
    try testing.expect(found_mismatch);
}
