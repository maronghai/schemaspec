const std = @import("std");
const ast = @import("../../types/ast.zig");
const diag = @import("../diagnostic.zig");
const type_map = @import("../../types/type_map.zig");
const ast_visitor = @import("../../ast_visitor.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const Field = ast.Field;
const Modifier = ast.Modifier;

const ModifierValidationCtx = struct {
    alloc: std.mem.Allocator,
    diagnostics: *diag.DiagnosticCollector,
};

fn visitFieldCheckModifiers(ctx: *ModifierValidationCtx, field: *const Field, _: ?[]const u8) void {
    for (field.modifiers) |mod| {
        switch (mod.kind) {
            .auto_inc_pk, .auto_inc => {
                if (!type_map.isNumericSymType(field.type_info) and !type_map.isDatetimeSymType(field.type_info)) {
                    const mod_name = if (mod.kind == .auto_inc_pk) "auto_increment_primary_key" else "auto_increment";
                    ctx.diagnostics.push(.{
                        .severity = .warning,
                        .line_no = mod.line_no,
                        .message = std.fmt.allocPrint(ctx.alloc, "'{s}' modifier has no effect on non-numeric/non-datetime type in field '{s}'", .{ mod_name, field.name }) catch return,
                    });
                }
            },
            .primary_key => {},
            .nullable => {},
            .unsigned => {
                if (!type_map.isNumericSymType(field.type_info)) {
                    ctx.diagnostics.push(.{
                        .severity = .warning,
                        .line_no = mod.line_no,
                        .message = std.fmt.allocPrint(ctx.alloc, "'unsigned' modifier has no effect on non-numeric type in field '{s}'", .{field.name}) catch return,
                    });
                }
            },
            .inline_unique => {},
            .inline_index => {},
            .virtual => {},
            .stored => {},
        }
    }
}

/// Validates that modifiers are used with compatible types.
pub fn run(ctx: *PassContext) !void {
    var vctx = ModifierValidationCtx{
        .alloc = ctx.alloc,
        .diagnostics = ctx.diagnostics,
    };

    const visitor = ast_visitor.AstVisitor(*ModifierValidationCtx){
        .context = &vctx,
        .visitField = visitFieldCheckModifiers,
    };

    visitor.walkResolvedTables(ctx.tables.items);
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const ResolvedTable = resolved_ast.ResolvedTable;


test "validate_type_modifiers: unsigned on numeric type — no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fields = try std.ArrayList(Field).initCapacity(alloc, 1);
    var field = test_helpers.makeTestField("count", .{ .simple = "n" });
    field.modifiers = &.{.{ .kind = .unsigned, .line_no = 1 }};
    try fields.append(alloc, field);

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = try fields.toOwnedSlice(alloc),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_type_modifiers: unsigned on string type — warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fields = try std.ArrayList(Field).initCapacity(alloc, 1);
    var field = test_helpers.makeTestField("name", .{ .simple = "s" });
    field.modifiers = &.{.{ .kind = .unsigned, .line_no = 1 }};
    try fields.append(alloc, field);

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = try fields.toOwnedSlice(alloc),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "unsigned") != null);
}

test "validate_type_modifiers: auto_inc on non-numeric non-datetime — warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fields = try std.ArrayList(Field).initCapacity(alloc, 1);
    var field = test_helpers.makeTestField("tag", .{ .simple = "s" });
    field.modifiers = &.{.{ .kind = .auto_inc_pk, .line_no = 1 }};
    try fields.append(alloc, field);

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "t",
        .comment = null,
        .engine = null,
        .fields = try fields.toOwnedSlice(alloc),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "auto_increment") != null);
}

test "validate_type_modifiers: empty modifiers — no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "t",
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
