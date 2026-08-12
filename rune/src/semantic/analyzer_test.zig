const std = @import("std");
const analyzer = @import("analyzer.zig");
const test_helpers = @import("test_helpers.zig");
const ast_mod = @import("../types/ast.zig");
const diag = @import("../diagnostic.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const symbol_table_mod = @import("../types/symbol_table.zig");
const PassContext = analyzer.PassContext;

const testing = std.testing;
const Field = ast_mod.Field;
const Modifier = ast_mod.Modifier;
const ResolvedTable = resolved_ast.ResolvedTable;

// ─── Tests ──────────────────────────────────────────────────

test "suffix inference: _id → int" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("user_id", .none);

    const a = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{.{
        .name = "order",
        .template_ref = null,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}), &.{});

    var sa = analyzer.SemanticAnalyzer.init(alloc);
    const result = try sa.analyze(a);

    try testing.expectEqual(@as(usize, 1), result.tables.len);
    try testing.expectEqual(@as(usize, 1), result.tables[0].fields.len);
    try testing.expectEqualStrings("n", result.tables[0].fields[0].type_info.simple);
}

test "suffix inference: _at → datetime" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("created_at", .none);

    const a = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{.{
        .name = "log",
        .template_ref = null,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}), &.{});

    var sa = analyzer.SemanticAnalyzer.init(alloc);
    const result = try sa.analyze(a);

    try testing.expectEqualStrings("t", result.tables[0].fields[0].type_info.simple);
}

test "suffix inference: _on → date" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("paid_on", .none);

    const a = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{.{
        .name = "payment",
        .template_ref = null,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}), &.{});

    var sa = analyzer.SemanticAnalyzer.init(alloc);
    const result = try sa.analyze(a);

    try testing.expectEqualStrings("d", result.tables[0].fields[0].type_info.simple);
}

test "suffix inference: explicit type wins over suffix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("point_id", .{ .varchar_explicit = 32 });

    const a = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{.{
        .name = "points",
        .template_ref = null,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}), &.{});

    var sa = analyzer.SemanticAnalyzer.init(alloc);
    const result = try sa.analyze(a);

    const fi = result.tables[0].fields[0].type_info;
    try testing.expect(std.meta.activeTag(fi) == .varchar_explicit);
}

test "suffix inference: no suffix keeps explicit type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestField("data", .{ .simple = "b" });

    const a = test_helpers.makeTestAst(alloc, try alloc.dupe(ast_mod.Table, &.{.{
        .name = "t",
        .template_ref = null,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    }}), &.{});

    var sa = analyzer.SemanticAnalyzer.init(alloc);
    const result = try sa.analyze(a);

    try testing.expectEqualStrings("b", result.tables[0].fields[0].type_info.simple);
}

// ─── Type Modifier Validation Tests ─────────────────────────

test "validate_type_modifiers: ++ on varchar produces warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mods = try alloc.alloc(Modifier, 1);
    mods[0] = .{ .kind = .auto_inc_pk, .line_no = 3 };
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestFieldWithMods("name", .{ .simple = "s" }, mods);

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

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext.init(alloc, &tables, null, std.StringHashMap(*const ast_mod.Template).init(alloc), std.StringHashMap(void).init(alloc), &diagnostics, symbol_table_mod.SymbolTable.init(alloc));
    try @import("pass/validate_type_modifiers.zig").run(&ctx);
    try testing.expect(diagnostics.diagnostics.items.len > 0);
}

test "validate_type_modifiers: u on varchar produces warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mods = try alloc.alloc(Modifier, 1);
    mods[0] = .{ .kind = .unsigned, .line_no = 2 };
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestFieldWithMods("tag", .{ .simple = "s" }, mods);

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

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext.init(alloc, &tables, null, std.StringHashMap(*const ast_mod.Template).init(alloc), std.StringHashMap(void).init(alloc), &diagnostics, symbol_table_mod.SymbolTable.init(alloc));
    try @import("pass/validate_type_modifiers.zig").run(&ctx);
    try testing.expect(diagnostics.diagnostics.items.len > 0);
}

test "validate_type_modifiers: ++ on n produces no warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mods = try alloc.alloc(Modifier, 1);
    mods[0] = .{ .kind = .auto_inc_pk, .line_no = 1 };
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestFieldWithMods("id", .{ .simple = "n" }, mods);

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

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext.init(alloc, &tables, null, std.StringHashMap(*const ast_mod.Template).init(alloc), std.StringHashMap(void).init(alloc), &diagnostics, symbol_table_mod.SymbolTable.init(alloc));
    try @import("pass/validate_type_modifiers.zig").run(&ctx);
    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_type_modifiers: + on t produces no warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mods = try alloc.alloc(Modifier, 1);
    mods[0] = .{ .kind = .auto_inc, .line_no = 1 };
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestFieldWithMods("created_at", .{ .simple = "t" }, mods);

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

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext.init(alloc, &tables, null, std.StringHashMap(*const ast_mod.Template).init(alloc), std.StringHashMap(void).init(alloc), &diagnostics, symbol_table_mod.SymbolTable.init(alloc));
    try @import("pass/validate_type_modifiers.zig").run(&ctx);
    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}

test "validate_type_modifiers: u on n produces no warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mods = try alloc.alloc(Modifier, 1);
    mods[0] = .{ .kind = .unsigned, .line_no = 1 };
    const fields = try alloc.alloc(Field, 1);
    fields[0] = test_helpers.makeTestFieldWithMods("count", .{ .simple = "n" }, mods);

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

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var ctx = PassContext.init(alloc, &tables, null, std.StringHashMap(*const ast_mod.Template).init(alloc), std.StringHashMap(void).init(alloc), &diagnostics, symbol_table_mod.SymbolTable.init(alloc));
    try @import("pass/validate_type_modifiers.zig").run(&ctx);
    try testing.expectEqual(@as(usize, 0), diagnostics.diagnostics.items.len);
}
