const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const Field = ast.Field;
const ResolvedTable = resolved_ast.ResolvedTable;
const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../../diagnostic.zig");

// ─── Resolve Composites ──────────────────────────────────────
// Expands composite type embeds (`*name` lines inside table bodies) in place.
// Runs after resolve_conditionals (conditional-block field indices are already
// consumed) and before autofk/suffix_inference (which must see final fields).

pub fn run(ctx: *PassContext) !void {
    // Build name → composite map; detect duplicate definitions.
    var comp_map = std.StringHashMap(*const ast.Composite).init(ctx.alloc);
    defer comp_map.deinit();
    for (ctx.composites) |*comp| {
        if (comp_map.contains(comp.name)) {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = comp.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "duplicate composite definition: '{s}'", .{comp.name}),
            });
            continue;
        }
        try comp_map.put(comp.name, comp);
    }

    // Track which composites get embedded (for the unused warning below).
    var used = std.StringHashMap(void).init(ctx.alloc);
    defer used.deinit();

    for (ctx.tables.items) |*table| {
        if (table.embeds.len == 0) continue;
        for (table.embeds) |e| {
            try used.put(e.name, {});
        }
        table.fields = try expandTable(ctx, comp_map, table);
        table.embeds = &.{};
    }

    // Warn about composites never embedded in any table.
    for (ctx.composites) |*comp| {
        if (!used.contains(comp.name)) {
            ctx.diagnostics.push(.{
                .severity = .warning,
                .line_no = comp.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "unused composite: '{s}' is defined but never embedded", .{comp.name}),
            });
        }
    }
}

/// Expand one table's fields: splice each embed's composite fields at its
/// recorded insert position. Positions refer to the literal (pre-expansion)
/// field list, so earlier expansions shift later positions.
fn expandTable(
    ctx: *PassContext,
    comp_map: std.StringHashMap(*const ast.Composite),
    table: *ResolvedTable,
) ![]Field {
    // Sort embeds by insert position ascending so splicing stays position-correct.
    const embeds = try ctx.alloc.dupe(ast.CompositeEmbed, table.embeds);
    std.mem.sort(ast.CompositeEmbed, embeds, {}, struct {
        fn lt(_: void, a: ast.CompositeEmbed, b: ast.CompositeEmbed) bool {
            return a.insert_pos < b.insert_pos;
        }
    }.lt);

    var out = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len + 8);
    var consumed: usize = 0; // fields copied from the original list so far
    for (embeds) |embed| {
        while (consumed < embed.insert_pos and consumed < table.fields.len) : (consumed += 1) {
            try out.append(ctx.alloc, table.fields[consumed]);
        }
        const comp = comp_map.get(embed.name) orelse {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = embed.line_no,
                .message = try std.fmt.allocPrint(ctx.alloc, "unknown composite: '{s}' is not defined", .{embed.name}),
            });
            continue;
        };
        for (comp.fields) |f| {
            if (std.mem.eql(u8, f.name, "...")) continue;
            try out.append(ctx.alloc, f);
        }
    }
    while (consumed < table.fields.len) : (consumed += 1) {
        try out.append(ctx.alloc, table.fields[consumed]);
    }
    return try out.toOwnedSlice(ctx.alloc);
}

// ─── Unit Tests ─────────────────────────────────────────────

fn makeField(name: []const u8) Field {
    return test_helpers.makeTestField(name, .{ .simple = "n" });
}

fn makeComposite(alloc: std.mem.Allocator, name: []const u8, field_names: []const []const u8, line_no: usize) !ast.Composite {
    const fields = try alloc.alloc(Field, field_names.len);
    for (field_names, 0..) |fn_, i| fields[i] = makeField(fn_);
    return .{ .name = name, .fields = fields, .line_no = line_no };
}

fn makeCtxWithComposites(
    alloc: std.mem.Allocator,
    tables: *std.ArrayList(ResolvedTable),
    diagnostics: *diag_mod.DiagnosticCollector,
    composites: []const ast.Composite,
) PassContext {
    var ctx = test_helpers.makePassCtx(alloc, tables, diagnostics, .{});
    ctx.composites = composites;
    return ctx;
}

test "resolve_composites: expands embed in place" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const comps = [_]ast.Composite{
        try makeComposite(alloc, "audit", &.{ "created_at", "updated_at" }, 1),
    };

    const fields = try alloc.alloc(Field, 2);
    fields[0] = makeField("id");
    fields[1] = makeField("name");

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    const embeds = try alloc.alloc(ast.CompositeEmbed, 1);
    embeds[0] = .{ .name = "audit", .insert_pos = 2, .line_no = 5 };
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .embeds = embeds,
        .line_no = 4,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithComposites(alloc, &tables, &diagnostics, &comps);
    try run(&ctx);

    const got = ctx.tables.items[0].fields;
    try testing.expectEqual(@as(usize, 4), got.len);
    try testing.expectEqualStrings("id", got[0].name);
    try testing.expectEqualStrings("name", got[1].name);
    try testing.expectEqualStrings("created_at", got[2].name);
    try testing.expectEqualStrings("updated_at", got[3].name);
    try testing.expectEqual(@as(usize, 0), ctx.tables.items[0].embeds.len);
}

test "resolve_composites: multiple embeds keep source order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const comps = [_]ast.Composite{
        try makeComposite(alloc, "audit", &.{ "created_at", "updated_at" }, 1),
        try makeComposite(alloc, "soft_delete", &.{"deleted_at"}, 3),
    };

    const fields = try alloc.alloc(Field, 2);
    fields[0] = makeField("id");
    fields[1] = makeField("total");

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    const embeds = try alloc.alloc(ast.CompositeEmbed, 2);
    embeds[0] = .{ .name = "audit", .insert_pos = 1, .line_no = 5 };
    embeds[1] = .{ .name = "soft_delete", .insert_pos = 2, .line_no = 7 };
    try tables.append(alloc, .{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .embeds = embeds,
        .line_no = 4,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithComposites(alloc, &tables, &diagnostics, &comps);
    try run(&ctx);

    const got = ctx.tables.items[0].fields;
    try testing.expectEqual(@as(usize, 5), got.len);
    try testing.expectEqualStrings("id", got[0].name);
    try testing.expectEqualStrings("created_at", got[1].name);
    try testing.expectEqualStrings("updated_at", got[2].name);
    try testing.expectEqualStrings("total", got[3].name);
    try testing.expectEqualStrings("deleted_at", got[4].name);
}

test "resolve_composites: unknown composite errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(Field, 1);
    fields[0] = makeField("id");

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    const embeds = try alloc.alloc(ast.CompositeEmbed, 1);
    embeds[0] = .{ .name = "nope", .insert_pos = 1, .line_no = 5 };
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .embeds = embeds,
        .line_no = 4,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithComposites(alloc, &tables, &diagnostics, &.{});
    try run(&ctx);

    try testing.expect(diagnostics.hasErrors());
    try testing.expect(std.mem.indexOf(u8, diagnostics.diagnostics.items[0].message, "unknown composite: 'nope'") != null);
}

test "resolve_composites: duplicate definition errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const comps = [_]ast.Composite{
        try makeComposite(alloc, "audit", &.{"created_at"}, 1),
        try makeComposite(alloc, "audit", &.{"updated_at"}, 5),
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 0);
    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithComposites(alloc, &tables, &diagnostics, &comps);
    try run(&ctx);

    try testing.expect(diagnostics.hasErrors());
    try testing.expect(std.mem.indexOf(u8, diagnostics.diagnostics.items[0].message, "duplicate composite definition") != null);
}

test "resolve_composites: unused composite warns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const comps = [_]ast.Composite{
        try makeComposite(alloc, "orphan", &.{"created_at"}, 1),
    };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 0);
    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtxWithComposites(alloc, &tables, &diagnostics, &comps);
    try run(&ctx);

    try testing.expect(!diagnostics.hasErrors());
    try testing.expect(diagnostics.diagnostics.items.len == 1);
    try testing.expect(std.mem.indexOf(u8, diagnostics.diagnostics.items[0].message, "unused composite: 'orphan'") != null);
}
