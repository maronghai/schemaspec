const std = @import("std");
const PassContext = @import("../pass_manager.zig").PassContext;
const ast_mod = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const ResolvedTable = resolved_ast.ResolvedTable;
const TypeInfo = ast_mod.TypeInfo;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");

// ─── Validate Unused Custom Types ────────────────────────────
// Detects custom types (~) that are defined but never referenced
// in any table field. Emits warnings for dead schema definitions.

pub fn run(ctx: *PassContext) !void {
    // Skip if no custom types defined
    if (ctx.schema) |schema| {
        if (schema.custom_types.len == 0) return;
    } else {
        return;
    }

    const custom_types = ctx.schema.?.custom_types;

    // Build a set of referenced custom type names
    var referenced = std.StringHashMap(void).init(ctx.alloc);
    defer referenced.deinit();

    // Scan all table fields for custom type references
    for (ctx.tables.items) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .simple => |type_name| {
                    referenced.put(type_name, {}) catch {};
                },
                else => {},
            }
        }
    }

    // Report warnings for unused custom types
    for (custom_types) |ct| {
        if (!referenced.contains(ct.name)) {
            ctx.diagnostics.push(.{
                .severity = .warning,
                .line_no = ct.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "custom type '{s}' is defined but never used", .{ct.name}),
            });
        }
    }
}

// ─── Tests ───────────────────────────────────────────────────

test "validate_unused_enums: no custom types" {
    const alloc = std.testing.allocator;
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 0);
    defer tables.deinit(alloc);

    var diag_collector = try diag_mod.DiagnosticCollector.init(alloc);
    defer diag_collector.deinit();

    var ctx = test_helpers.makePassCtx(alloc, &tables, &diag_collector, .{});

    try run(&ctx);
    // No schema = no warnings
}

test "validate_unused_enums: all used" {
    const alloc = std.testing.allocator;
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    defer tables.deinit(alloc);

    // Table with a field referencing custom type "Status"
    const fields = try alloc.alloc(ast_mod.Field, 1);
    defer alloc.free(fields);
    fields[0] = test_helpers.makeTestField("status", .{ .simple = "Status" });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    const schema = ast_mod.Schema{
        .name = "test",
        .charset = null,
        .autofk = false,
        .custom_types = &.{
            .{
                .name = "Status",
                .base = .{ .simple = "s" },
                .dialect_overrides = &.{},
                .line_no = 1,
            },
        },
        .line_no = 1,
    };

    var diag_collector = try diag_mod.DiagnosticCollector.init(alloc);
    defer diag_collector.deinit();

    var ctx = test_helpers.makePassCtx(alloc, &tables, &diag_collector, .{ .schema = schema });

    try run(&ctx);
    // "Status" is used, no warnings expected
    try std.testing.expectEqual(@as(usize, 0), diag_collector.diagnostics.items.len);
}

test "validate_unused_enums: unused type detected" {
    const alloc = std.testing.allocator;
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    defer tables.deinit(alloc);

    // Table with a field NOT referencing custom type "UnusedType"
    const fields = try alloc.alloc(ast_mod.Field, 1);
    defer alloc.free(fields);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    const schema = ast_mod.Schema{
        .name = "test",
        .charset = null,
        .autofk = false,
        .custom_types = &.{
            .{
                .name = "UnusedType",
                .base = .{ .simple = "s" },
                .dialect_overrides = &.{},
                .line_no = 5,
            },
        },
        .line_no = 1,
    };

    var diag_collector = try diag_mod.DiagnosticCollector.init(alloc);
    defer diag_collector.deinit();

    var ctx = test_helpers.makePassCtx(alloc, &tables, &diag_collector, .{ .schema = schema });

    try run(&ctx);
    // "UnusedType" is not used, should get 1 warning
    try std.testing.expectEqual(@as(usize, 1), diag_collector.diagnostics.items.len);
    const warning = diag_collector.diagnostics.items[0];
    try std.testing.expectEqual(diag_mod.Severity.warning, warning.severity);
    try std.testing.expect(std.mem.indexOf(u8, warning.message, "UnusedType") != null);
    // Free allocated message
    alloc.free(warning.message);
}
