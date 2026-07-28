const std = @import("std");
const ast = @import("../../types/ast.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const FkDecl = ast.FkDecl;
const ResolvedTable = resolved_ast.ResolvedTable;

const VisitStatus = enum { visiting, visited };

/// Validate that FK target fields exist in the referenced table.
fn validateFkTargetFields(
    ctx: *PassContext,
    table: ResolvedTable,
    fk: FkDecl,
) !void {
    if (fk.ref_table.len == 0) return;

    for (fk.ref_fields) |ref_field| {
        if (ctx.symbol_table.lookupField(fk.ref_table, ref_field) == null) {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = fk.line_no,
                .message = std.fmt.allocPrint(ctx.alloc, "FK references non-existent field '{s}' in table '{s}' (from table '{s}')", .{ ref_field, fk.ref_table, table.name }) catch return,
            });
        }
    }
}

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

/// Schema-level semantic validation: duplicate table names, circular FKs, FK target field existence,
/// self-referencing FK field count mismatch.
/// Uses the SymbolTable built by the resolve_names pass.
pub fn run(ctx: *PassContext) !void {
    // Validate duplicate table names
    var seen_tables = std.StringHashMap(usize).init(ctx.alloc);
    for (ctx.tables.items, 0..) |table, i| {
        if (seen_tables.get(table.name)) |first_idx| {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = table.line_no,
                .message = std.fmt.allocPrint(ctx.alloc, "duplicate table name '{s}' (first declared at table #{d})", .{ table.name, first_idx + 1 }) catch return,
            });
        } else {
            try seen_tables.put(table.name, i);
        }
    }

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

    // Validate FK target fields using SymbolTable
    for (ctx.tables.items) |table| {
        for (table.fks) |fk| {
            try validateFkTargetFields(ctx, table, fk);
        }
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try validateFkTargetFields(ctx, table, fk);
            }
        }
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

    // Warn about unused templates
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
const symbol_table_mod = @import("../../types/symbol_table.zig");

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector) PassContext {
    var st = symbol_table_mod.SymbolTable.init(alloc);
    for (tables.items) |*t| {
        _ = st.registerTable(t.name, t) catch {};
    }
    return .{
        .alloc = alloc,
        .tables = tables,
        .schema = null,
        .diagnostics = diagnostics,
        .symbol_table = st,
    };
}

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

test "validate_schema: duplicate table names emit diagnostic" {
    const alloc = testing.allocator;

    const a_fields = try alloc.alloc(ast.Field, 1);
    a_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    const b_fields = try alloc.alloc(ast.Field, 1);
    b_fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = a_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = b_fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics);
    try run(&ctx);

    var found_duplicate = false;
    for (diagnostics.diagnostics.items) |d| {
        if (std.mem.indexOf(u8, d.message, "duplicate table name") != null) {
            found_duplicate = true;
            break;
        }
    }
    try testing.expect(found_duplicate);
}

test "validate_schema: circular FK emits diagnostic" {
    const alloc = testing.allocator;

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

test "validate_schema: non-circular FK produces no circular diagnostic" {
    const alloc = testing.allocator;

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

test "validate_schema: unused template emits warning" {
    const alloc = testing.allocator;

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

test "validate_schema: used template produces no unused warning" {
    const alloc = testing.allocator;

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
