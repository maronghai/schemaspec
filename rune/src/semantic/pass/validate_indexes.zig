const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const edit_distance = @import("../../utils/edit_distance.zig");

/// Validate index declarations: duplicate names, duplicate definitions, non-existent column references.
pub fn run(ctx: *PassContext) !void {
    for (ctx.tables.items) |*table| {
        try checkDuplicateNames(ctx, table);
        try checkSemanticDuplicates(ctx, table);
        try checkColumnRefs(ctx, table);
    }
}

/// Check for duplicate index names within a table.
fn checkDuplicateNames(ctx: *PassContext, table: *const resolved_ast.ResolvedTable) !void {
    for (table.indexes, 0..) |idx, i| {
        if (idx.name.len == 0) continue;
        for (table.indexes[i + 1 ..]) |other| {
            if (std.mem.eql(u8, idx.name, other.name)) {
                ctx.diagnostics.push(.{
                    .severity = .warning,
                    .line_no = other.line_no,
                    .message = std.fmt.allocPrint(ctx.alloc, "duplicate index name '{s}' in table '{s}'", .{ idx.name, table.name }) catch return,
                });
            }
        }
    }
}

/// Check for semantically identical indexes (same fields + kind + descending, different name).
fn checkSemanticDuplicates(ctx: *PassContext, table: *const resolved_ast.ResolvedTable) !void {
    for (table.indexes, 0..) |idx, i| {
        for (table.indexes[i + 1 ..]) |other| {
            if (idx.fields.len != other.fields.len) continue;
            if (idx.kind != other.kind) continue;
            var same_fields = true;
            for (idx.fields, 0..) |f, fi| {
                if (!std.mem.eql(u8, f, other.fields[fi])) {
                    same_fields = false;
                    break;
                }
            }
            if (!same_fields) continue;
            var same_desc = true;
            for (idx.descending, 0..) |d, di| {
                if (di >= other.descending.len or d != other.descending[di]) {
                    same_desc = false;
                    break;
                }
            }
            if (!same_desc) continue;
            if (idx.name.len > 0 and other.name.len > 0 and !std.mem.eql(u8, idx.name, other.name)) {
                ctx.diagnostics.push(.{
                    .severity = .warning,
                    .line_no = other.line_no,
                    .message = std.fmt.allocPrint(ctx.alloc, "index '{s}' is semantically identical to '{s}' in table '{s}'", .{ other.name, idx.name, table.name }) catch return,
                });
            }
        }
    }
}

/// Check for indexes referencing non-existent columns (with "did you mean?" suggestions).
fn checkColumnRefs(ctx: *PassContext, table: *const resolved_ast.ResolvedTable) !void {
    // Build a set of valid column names for O(1) lookup.
    var col_set = std.StringHashMap(void).init(ctx.alloc);
    defer col_set.deinit();
    for (table.fields) |col| {
        col_set.put(col.name, {}) catch {};
    }

    for (table.indexes) |idx| {
        for (idx.fields) |field_name| {
            if (!col_set.contains(field_name)) {
                var col_names = try std.ArrayList([]const u8).initCapacity(ctx.alloc, table.fields.len);
                for (table.fields) |col| {
                    try col_names.append(ctx.alloc, col.name);
                }
                const suggestion = edit_distance.suggestClosest(field_name, col_names.items, 3);
                const msg = if (suggestion) |s|
                    std.fmt.allocPrint(ctx.alloc, "index '{s}' references non-existent column '{s}' in table '{s}' — did you mean '{s}'?", .{ idx.name, field_name, table.name, s.match }) catch return
                else
                    std.fmt.allocPrint(ctx.alloc, "index '{s}' references non-existent column '{s}' in table '{s}'", .{ idx.name, field_name, table.name }) catch return;
                ctx.diagnostics.push(.{
                    .severity = .warning,
                    .line_no = idx.line_no,
                    .message = msg,
                });
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

test "validate_indexes: duplicate index name emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("email", .{ .simple = "s" });

    const indexes = try alloc.alloc(ast.IndexDecl, 2);
    indexes[0] = .{ .kind = .regular, .name = "idx_name", .fields = try alloc.dupe([]const u8, &.{"name"}), .descending = &.{false}, .line_no = 2 };
    indexes[1] = .{ .kind = .regular, .name = "idx_name", .fields = try alloc.dupe([]const u8, &.{"email"}), .descending = &.{false}, .line_no = 3 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "duplicate index name 'idx_name'") != null);
}

test "validate_indexes: index on non-existent column emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });

    const indexes = try alloc.alloc(ast.IndexDecl, 1);
    indexes[0] = .{ .kind = .regular, .name = "idx_missing", .fields = try alloc.dupe([]const u8, &.{"nonexistent_col"}), .descending = &.{false}, .line_no = 2 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "non-existent column 'nonexistent_col'") != null);
}

test "validate_indexes: valid index produces no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("email", .{ .simple = "s" });

    const indexes = try alloc.alloc(ast.IndexDecl, 1);
    indexes[0] = .{ .kind = .regular, .name = "idx_name", .fields = try alloc.dupe([]const u8, &.{"name"}), .descending = &.{false}, .line_no = 2 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_indexes: semantically identical indexes emit warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("email", .{ .simple = "s" });

    const indexes = try alloc.alloc(ast.IndexDecl, 2);
    indexes[0] = .{ .kind = .regular, .name = "idx_name_email", .fields = try alloc.dupe([]const u8, &.{ "name", "email" }), .descending = &.{ false, false }, .line_no = 2 };
    indexes[1] = .{ .kind = .regular, .name = "idx_composite", .fields = try alloc.dupe([]const u8, &.{ "name", "email" }), .descending = &.{ false, false }, .line_no = 3 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    var found_semantic_dup = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "semantically identical") != null) {
            found_semantic_dup = true;
            break;
        }
    }
    try testing.expect(found_semantic_dup);
}

test "validate_indexes: index on misspelled column suggests correction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 2);
    fields[0] = test_helpers.makeTestField("username", .{ .simple = "s" });
    fields[1] = test_helpers.makeTestField("email", .{ .simple = "s" });

    const indexes = try alloc.alloc(ast.IndexDecl, 1);
    indexes[0] = .{ .kind = .regular, .name = "idx_name", .fields = try alloc.dupe([]const u8, &.{"usrname"}), .descending = &.{false}, .line_no = 2 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "did you mean 'username'") != null);
}
