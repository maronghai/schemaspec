const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;
const ResolvedTable = resolved_ast.ResolvedTable;
const TypeInfo = ast.TypeInfo;

/// Validate FK field type compatibility: warn when FK field types don't match
/// the referenced table's PK/unique field types.
///
/// This catches common schema bugs like integer FKs referencing string PKs,
/// which may compile but fail at the database level.
pub fn run(ctx: *PassContext) !void {
    // Build a map from table name → ResolvedTable for FK reference lookup.
    var table_map = std.StringHashMap(*const ResolvedTable).init(ctx.alloc);
    for (ctx.tables.items) |*table| {
        _ = table_map.put(table.name, table) catch {};
    }

    for (ctx.tables.items) |table| {
        for (table.fks) |fk| {
            try validateFk(ctx, &table_map, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try validateFk(ctx, &table_map, table, fk);
            }
        }
    }
}

/// Validate a single FK declaration's type compatibility.
fn validateFk(
    ctx: *PassContext,
    table_map: *const std.StringHashMap(*const ResolvedTable),
    table: ResolvedTable,
    fk: FkDecl,
) !void {
    // Skip FKs with no reference table (handled by validate_fk_targets).
    if (fk.ref_table.len == 0) return;

    const ref_table = table_map.get(fk.ref_table) orelse return;

    // For each FK field, find the corresponding ref field and compare types.
    // `continue` per pair — an early `return` here silently skipped every
    // mismatch after the first unresolved/missing field in compound FKs.
    for (fk.fields, 0..) |fk_field, i| {
        const ref_field_name = if (i < fk.ref_fields.len) fk.ref_fields[i] else {
            // Not enough ref fields — FK has fewer fields than ref_fields.
            // This is likely a parse error; skip type check.
            return;
        };

        const fk_field_type = findFieldType(table, fk_field) orelse continue;
        const ref_field_type = findFieldType(ref_table.*, ref_field_name) orelse continue;

        // Skip if either type is unresolved (.none).
        if (std.meta.activeTag(fk_field_type.*) == .none or std.meta.activeTag(ref_field_type.*) == .none) continue;

        // Skip if types are exactly equal — no issue.
        if (fk_field_type.eql(ref_field_type.*)) continue;

        // Types differ — check if they're at least in the same category.
        const same_category = (fk_field_type.isNumeric() and ref_field_type.isNumeric()) or
            (fk_field_type.isString() and ref_field_type.isString()) or
            (fk_field_type.isDatetime() and ref_field_type.isDatetime()) or
            (fk_field_type.isBoolean() and ref_field_type.isBoolean());

        const severity: @import("../../diagnostic.zig").Severity = if (same_category) .note else .warning;

        ctx.diagnostics.push(.{
            .severity = severity,
            .line_no = table.line_no,
            .message = std.fmt.allocPrint(
                ctx.alloc,
                "FK field '{s}' type does not match referenced field '{s}.{s}' type in table '{s}'",
                .{ fk_field, fk.ref_table, ref_field_name, table.name },
            ) catch return,
        });
    }
}

/// Find the TypeInfo for a named field in a table.
fn findFieldType(table: ResolvedTable, field_name: []const u8) ?*const TypeInfo {
    for (table.fields) |*field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return &field.type_info;
        }
    }
    return null;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../../diagnostic.zig");

fn makeTable(name: []const u8, fields: []ast.Field, fks: []const FkDecl) ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    };
}

test "validate_fk_types: integer FK to integer PK produces no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_fk_types: string FK to string PK produces no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("uuid", .{ .simple = "s" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_uuid", .{ .simple = "s" });

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_uuid"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"uuid"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_fk_types: string FK to integer PK emits warning (cross-category)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "s" }); // string FK!

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const d = diagnostics.diagnostics.items[0];
    try testing.expectEqual(@import("../../diagnostic.zig").Severity.warning, d.severity);
}

test "validate_fk_types: integer FK to string PK emits warning (cross-category)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("uuid", .{ .simple = "s" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" }); // integer FK!

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"uuid"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const d = diagnostics.diagnostics.items[0];
    try testing.expectEqual(@import("../../diagnostic.zig").Severity.warning, d.severity);
}

test "validate_fk_types: same-category mismatch emits note" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" }); // integer

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "m" }); // money (numeric but different)

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const d = diagnostics.diagnostics.items[0];
    try testing.expectEqual(@import("../../diagnostic.zig").Severity.note, d.severity);
}

test "validate_fk_types: same type FK to PK produces no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" }); // integer

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" }); // integer (same type)

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    // Same type produces no diagnostic.
    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_fk_types: inline FK type mismatch emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = .{
        .name = "user_id",
        .type_info = .{ .simple = "b" }, // boolean FK!
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = .{
            .fields = try alloc.dupe([]const u8, &.{"user_id"}),
            .ref_table = "users",
            .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
            .actions = &.{},
            .line_no = 1,
        },
        .comment = null,
        .line_no = 1,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, &.{}));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "FK field 'user_id' type does not match") != null);
}

test "validate_fk_types: multiple FKs with mixed compatibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const user_fields = try alloc.alloc(ast.Field, 1);
    user_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const order_fields = try alloc.alloc(ast.Field, 2);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" }); // match
    order_fields[1] = test_helpers.makeTestField("admin_id", .{ .simple = "s" }); // mismatch

    const fks = try alloc.alloc(FkDecl, 2);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };
    fks[1] = .{
        .fields = try alloc.dupe([]const u8, &.{"admin_id"}),
        .ref_table = "users",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 4,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, makeTable("users", user_fields, &.{}));
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    // Only admin_id should produce a diagnostic (user_id matches).
    try testing.expectEqual(@as(usize, 1), diagnostics.diagnostics.items.len);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "admin_id") != null);
}

test "validate_fk_types: FK to non-existent table produces no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const order_fields = try alloc.alloc(ast.Field, 1);
    order_fields[0] = test_helpers.makeTestField("user_id", .{ .simple = "n" });

    const fks = try alloc.alloc(FkDecl, 1);
    fks[0] = .{
        .fields = try alloc.dupe([]const u8, &.{"user_id"}),
        .ref_table = "nonexistent",
        .ref_fields = try alloc.dupe([]const u8, &.{"id"}),
        .actions = &.{},
        .line_no = 3,
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, makeTable("orders", order_fields, fks));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{ .init_symbol_table = true });
    try run(&ctx);

    // No diagnostic — validate_fk_targets handles missing tables.
    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
