const std = @import("std");
const ast = @import("../../types/ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;

/// Warn about templates that are defined but never referenced by any table.
pub fn run(ctx: *PassContext) !void {
    var tit = ctx.templates.iterator();
    while (tit.next()) |entry| {
        const tname = entry.key_ptr.*;
        if (tname.len == 0) continue; // skip unnamed/default template
        if (!ctx.template_refs.contains(tname)) {
            const tmpl = entry.value_ptr.*;
            ctx.diagnostics.push(.{
                .severity = .warning,
                .line_no = tmpl.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "template '{s}' is defined but never used", .{tname}),
            });
        }
    }
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const resolved_ast = @import("../../types/resolved_ast.zig");
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");
const symbol_table_mod = @import("../../types/symbol_table.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeCtxWithTemplates(
    alloc: std.mem.Allocator,
    tables: *std.ArrayList(ResolvedTable),
    diagnostics: *diag_mod.DiagnosticCollector,
    templates: std.StringHashMap(*const ast.Template),
    template_refs: std.StringHashMap(void),
) PassContext {
    var st = symbol_table_mod.SymbolTable.init(alloc);
    for (tables.items) |*t| {
        _ = st.registerTable(t.name, t) catch {};
    }
    return .{
        .alloc = alloc,
        .tables = tables,
        .schema = null,
        .templates = templates,
        .template_refs = template_refs,
        .diagnostics = diagnostics,
        .symbol_table = st,
    };
}

test "validate_unused_templates: unused template emits warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    const unused_tmpl = try alloc.create(ast.Template);
    unused_tmpl.* = .{ .name = "base", .parents = &.{}, .fields = fields, .slot_index = null, .line_no = 1 };

    var templates = std.StringHashMap(*const ast.Template).init(alloc);
    try templates.put("base", unused_tmpl);

    const template_refs = std.StringHashMap(void).init(alloc);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithTemplates(alloc, &tables, &diagnostics, templates, template_refs);
    try run(&ctx);

    var found_unused = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "never used") != null) {
            found_unused = true;
            break;
        }
    }
    try testing.expect(found_unused);
}

test "validate_unused_templates: used template produces no warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });

    const used_tmpl = try alloc.create(ast.Template);
    used_tmpl.* = .{ .name = "base", .parents = &.{}, .fields = fields, .slot_index = null, .line_no = 1 };

    var templates = std.StringHashMap(*const ast.Template).init(alloc);
    try templates.put("base", used_tmpl);

    var template_refs = std.StringHashMap(void).init(alloc);
    try template_refs.put("base", {});

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithTemplates(alloc, &tables, &diagnostics, templates, template_refs);
    try run(&ctx);

    for (diagnostics.diagnostics.items) |d| {
        try testing.expect(std.mem.indexOf(u8, d.message, "never used") == null);
    }
}
