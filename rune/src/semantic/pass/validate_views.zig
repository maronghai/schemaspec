const std = @import("std");
const pass_manager = @import("../pass_manager.zig");
const PassContext = pass_manager.PassContext;
const testing = std.testing;
const View = @import("../../types/ast.zig").View;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const Field = @import("../../types/ast.zig").Field;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

// ─── Validate Views ──────────────────────────────────────────
// Semantic pass that validates view definitions:
// 1. No duplicate view names
// 2. View queries reference tables that exist in the schema

pub fn run(ctx: *PassContext) !void {
    // Collect table names for reference checking
    var table_names = std.StringHashMap(void).init(ctx.alloc);
    defer table_names.deinit();
    for (ctx.tables.items) |table| {
        try table_names.put(table.name, {});
    }

    // Check for duplicate view names and validate references
    var seen_views = std.StringHashMap(void).init(ctx.alloc);
    defer seen_views.deinit();

    for (ctx.views) |view| {
        // Check for duplicate view names
        if (seen_views.contains(view.name)) {
            ctx.diagnostics.record(.{
                .severity = .@"error",
                .line_no = view.line_no,
                .col = 0,
                .message = "duplicate view name",
                .actual = view.name,
            });
            continue;
        }
        try seen_views.put(view.name, {});

        // Check that view query references existing tables (basic heuristic)
        // Look for FROM <table> and JOIN <table> patterns
        if (view.query.len > 0) {
            try checkQueryReferences(ctx, &table_names, view.query, view.name, view.line_no);
        }
    }
}

/// Check that table references in a view query exist in the schema.
/// Uses a simple heuristic: looks for FROM <word> and JOIN <word> patterns.
fn checkQueryReferences(
    ctx: *PassContext,
    table_names: *const std.StringHashMap(void),
    query: []const u8,
    view_name: []const u8,
    line_no: usize,
) !void {
    var upper_query = try ctx.alloc.alloc(u8, query.len);
    defer ctx.alloc.free(upper_query);
    for (query, 0..) |c, i| {
        upper_query[i] = std.ascii.toUpper(c);
    }

    // Simple state machine to find table references after FROM/JOIN keywords
    var i: usize = 0;
    while (i < upper_query.len) {
        // Look for FROM keyword
        if (i + 4 < upper_query.len and std.mem.eql(u8, upper_query[i .. i + 4], "FROM")) {
            i += 4;
            // Skip whitespace
            while (i < upper_query.len and upper_query[i] == ' ') : (i += 1) {}
            // Extract table name (until space, comma, newline, or end)
            const start = i;
            while (i < upper_query.len and upper_query[i] != ' ' and upper_query[i] != ',' and upper_query[i] != '\n') : (i += 1) {}
            if (i > start) {
                const table_ref = query[start..i];
                // Skip subquery markers and quoted identifiers
                if (table_ref[0] != '(' and table_ref[0] != '"' and table_ref[0] != '`' and table_ref[0] != '\'') {
                    if (!table_names.contains(table_ref)) {
                        const msg = try std.fmt.allocPrint(ctx.alloc, "view '{s}' references unknown table '{s}'", .{ view_name, table_ref });
                        ctx.diagnostics.record(.{
                            .severity = .warning,
                            .line_no = line_no,
                            .col = 0,
                            .message = msg,
                        });
                    }
                }
            }
            continue;
        }

        // Look for JOIN keyword
        if (i + 4 < upper_query.len and std.mem.eql(u8, upper_query[i .. i + 4], "JOIN")) {
            i += 4;
            // Skip whitespace
            while (i < upper_query.len and upper_query[i] == ' ') : (i += 1) {}
            // Extract table name
            const start = i;
            while (i < upper_query.len and upper_query[i] != ' ' and upper_query[i] != ',' and upper_query[i] != '\n') : (i += 1) {}
            if (i > start) {
                const table_ref = query[start..i];
                if (table_ref[0] != '(' and table_ref[0] != '"' and table_ref[0] != '`' and table_ref[0] != '\'') {
                    if (!table_names.contains(table_ref)) {
                        const msg = try std.fmt.allocPrint(ctx.alloc, "view '{s}' references unknown table '{s}'", .{ view_name, table_ref });
                        ctx.diagnostics.record(.{
                            .severity = .warning,
                            .line_no = line_no,
                            .col = 0,
                            .message = msg,
                        });
                    }
                }
            }
            continue;
        }

        i += 1;
    }
}

// ─── Tests ──────────────────────────────────────────────────

fn makeTestField(name: []const u8) Field {
    return .{
        .name = name,
        .type_info = .{ .simple = "n" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn makeTestTable(name: []const u8) ResolvedTable {
    return .{
        .name = name,
        .fields = &.{},
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = &.{},
        .line_no = 1,
    };
}

test "validate_views: no views passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, makeTestTable("users"));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.views = &.{};

    try run(&ctx);
    try testing.expectEqual(@as(usize, 0), ctx.diagnostics.diagnostics.items.len);
}

test "validate_views: valid view passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, makeTestTable("users"));

    const views = try alloc.alloc(View, 1);
    views[0] = .{
        .name = "active_users",
        .query = "SELECT * FROM users WHERE active = 1",
        .comment = null,
        .line_no = 1,
    };

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.views = views;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 0), ctx.diagnostics.diagnostics.items.len);
}

test "validate_views: duplicate view name produces error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, makeTestTable("users"));

    const views = try alloc.alloc(View, 2);
    views[0] = .{
        .name = "active_users",
        .query = "SELECT * FROM users",
        .comment = null,
        .line_no = 1,
    };
    views[1] = .{
        .name = "active_users",
        .query = "SELECT * FROM users WHERE active = 1",
        .comment = null,
        .line_no = 5,
    };

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.views = views;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 1), ctx.diagnostics.diagnostics.items.len);
    try testing.expectEqualStrings("duplicate view name", ctx.diagnostics.diagnostics.items[0].message);
}

test "validate_views: unknown table reference produces warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, makeTestTable("users"));

    const views = try alloc.alloc(View, 1);
    views[0] = .{
        .name = "user_orders",
        .query = "SELECT * FROM orders WHERE user_id = 1",
        .comment = null,
        .line_no = 1,
    };

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.views = views;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 1), ctx.diagnostics.diagnostics.items.len);
    try testing.expect(ctx.diagnostics.diagnostics.items[0].message.len > 0);
}
