const std = @import("std");
const ast = @import("../../types/ast.zig");
const PassContext = @import("../analyzer.zig").PassContext;
const symbol_table = @import("../../types/symbol_table.zig");

// ─── resolve_names pass ─────────────────────────────────────────
// Builds a SymbolTable and validates name uniqueness.
// Runs after validate_template_types (templates are resolved).
// Provides the SymbolTable on PassContext for downstream passes.

/// Build the symbol table from resolved tables and templates.
/// Validates that no two tables share the same name, and no table
/// name conflicts with a template name.
pub fn run(ctx: *PassContext) !void {
    var st = symbol_table.SymbolTable.init(ctx.alloc);

    // Register templates
    var templ_it = ctx.templates.iterator();
    while (templ_it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (st.contains(name)) {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = 0,
                .message = std.fmt.allocPrint(ctx.alloc, "name conflict: '{s}' is used as both a template and a table", .{name}) catch return,
            });
            continue;
        }
        _ = try st.registerTemplate(name);
    }

    // Register tables (skip empty names or parser artifacts like ">")
    for (ctx.tables.items) |*table| {
        if (table.name.len == 0 or std.mem.eql(u8, table.name, ">") or std.mem.eql(u8, table.name, "+")) continue;
        if (st.contains(table.name)) {
            ctx.diagnostics.push(.{
                .severity = .@"error",
                .line_no = table.line_no,
                .message = std.fmt.allocPrint(ctx.alloc, "duplicate name: '{s}' is defined more than once", .{table.name}) catch return,
            });
            continue;
        }
        _ = try st.registerTable(table.name, table);
    }

    // Store the symbol table in PassContext for downstream passes
    ctx.symbol_table = st;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../diagnostic.zig");
const resolved_ast = @import("../../types/resolved_ast.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeCtx(alloc: std.mem.Allocator, tables: *std.ArrayList(ResolvedTable), diagnostics: *diag_mod.DiagnosticCollector, templates: std.StringHashMap(*const ast.Template)) PassContext {
    return .{
        .alloc = alloc,
        .tables = tables,
        .schema = null,
        .templates = templates,
        .diagnostics = diagnostics,
    };
}

test "resolve_names: duplicate table name emits diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(ast.Field, 1);
    fields[0] = test_helpers.makeTestField("id", .{ .simple = "n" });

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 2);
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    });
    try tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 5,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    const templates = std.StringHashMap(*const ast.Template).init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics, templates);
    try run(&ctx);

    try testing.expect(diagnostics.diagnostics.items.len > 0);
    const msg = diagnostics.diagnostics.items[0].message;
    try testing.expect(std.mem.indexOf(u8, msg, "duplicate name: 'users'") != null);
}

test "resolve_names: valid tables populate symbol table" {
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

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    const templates = std.StringHashMap(*const ast.Template).init(alloc);
    var ctx = makeCtx(alloc, &tables, &diagnostics, templates);
    try run(&ctx);

    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
    try testing.expect(ctx.symbol_table.lookupTable("users") != null);
}
