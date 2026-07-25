const std = @import("std");
const ast = @import("../../types/ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const TypeInfo = ast.TypeInfo;

/// Template type consistency: warn when child template overrides parent field with different type.
pub fn run(ctx: *PassContext) !void {
    var it = ctx.templates.iterator();
    while (it.next()) |entry| {
        const tmpl = entry.value_ptr.*;
        for (tmpl.parents) |parent_name| {
            if (ctx.templates.get(parent_name)) |parent_tmpl| {
                var parent_fields = std.StringHashMap(TypeInfo).init(ctx.alloc);
                defer parent_fields.deinit();
                for (parent_tmpl.fields) |f| {
                    if (std.mem.eql(u8, f.name, "...")) continue;
                    try parent_fields.put(f.name, f.type_info);
                }
                for (tmpl.fields) |f| {
                    if (std.mem.eql(u8, f.name, "...")) continue;
                    if (parent_fields.get(f.name)) |parent_ti| {
                        if (!f.type_info.eql(parent_ti)) {
                            const tname = tmpl.name orelse "";
                            ctx.diagnostics.push(.{
                                .severity = .warning,
                                .line_no = f.line_no,
                                .message = try std.fmt.allocPrint(ctx.alloc, "template '{s}' overrides field '{s}' with different type (parent: {s}, child: {s})", .{ tname, f.name, @tagName(std.meta.activeTag(parent_ti)), @tagName(std.meta.activeTag(f.type_info)) }),
                            });
                        }
                    }
                }
            }
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeCtx(alloc: std.mem.Allocator, diagnostics: *diag_mod.DiagnosticCollector, templates: std.StringHashMap(*const ast.Template)) PassContext {
    var tables = std.ArrayList(ResolvedTable).init(alloc);
    return .{
        .alloc = alloc,
        .tables = &tables,
        .schema = null,
        .templates = templates,
        .diagnostics = diagnostics,
    };
}

test "validate_template_types: child overrides parent field type emits diagnostic" {
    const alloc = testing.allocator;

    const parent_fields = try alloc.alloc(ast.Field, 1);
    parent_fields[0] = test_helpers.makeTestField("status", .{ .simple = "n" });

    const child_fields = try alloc.alloc(ast.Field, 1);
    child_fields[0] = test_helpers.makeTestField("status", .{ .simple = "s" });

    const parent_tmpl = try alloc.create(ast.Template);
    parent_tmpl.* = .{ .name = "base", .parents = &.{}, .fields = parent_fields, .slot_index = null, .line_no = 1 };

    const child_tmpl = try alloc.create(ast.Template);
    child_tmpl.* = .{ .name = "extended", .parents = try alloc.dupe([]const u8, &.{"base"}), .fields = child_fields, .slot_index = null, .line_no = 5 };

    var templates = std.StringHashMap(*const ast.Template).init(alloc);
    try templates.put("base", parent_tmpl);
    try templates.put("extended", child_tmpl);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &diagnostics, templates);
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "overrides field 'status'") != null);
}

test "validate_template_types: same type produces no diagnostic" {
    const alloc = testing.allocator;

    const parent_fields = try alloc.alloc(ast.Field, 1);
    parent_fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });

    const child_fields = try alloc.alloc(ast.Field, 1);
    child_fields[0] = test_helpers.makeTestField("name", .{ .simple = "s" });

    const parent_tmpl = try alloc.create(ast.Template);
    parent_tmpl.* = .{ .name = "base", .parents = &.{}, .fields = parent_fields, .slot_index = null, .line_no = 1 };

    const child_tmpl = try alloc.create(ast.Template);
    child_tmpl.* = .{ .name = "extended", .parents = try alloc.dupe([]const u8, &.{"base"}), .fields = child_fields, .slot_index = null, .line_no = 5 };

    var templates = std.StringHashMap(*const ast.Template).init(alloc);
    try templates.put("base", parent_tmpl);
    try templates.put("extended", child_tmpl);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &diagnostics, templates);
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
