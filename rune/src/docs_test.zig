const std = @import("std");
const testing = std.testing;
const docs = @import("docs.zig");
const resolved_ast = @import("types/resolved_ast.zig");
const ast_mod = @import("types/ast.zig");

// ─── Helpers ─────────────────────────────────────────────────────

fn makeField(name: []const u8, type_info: ast_mod.TypeInfo) ast_mod.Field {
    return .{
        .name = name,
        .type_info = type_info,
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn allocFields(alloc: std.mem.Allocator, items: []const ast_mod.Field) ![]ast_mod.Field {
    const slice = try alloc.alloc(ast_mod.Field, items.len);
    for (items, 0..) |item, i| slice[i] = item;
    return slice;
}

fn allocTables(alloc: std.mem.Allocator, items: []const resolved_ast.ResolvedTable) ![]resolved_ast.ResolvedTable {
    const slice = try alloc.alloc(resolved_ast.ResolvedTable, items.len);
    for (items, 0..) |item, i| slice[i] = item;
    return slice;
}

fn allocViews(alloc: std.mem.Allocator, items: []const ast_mod.View) ![]ast_mod.View {
    const slice = try alloc.alloc(ast_mod.View, items.len);
    for (items, 0..) |item, i| slice[i] = item;
    return slice;
}

fn makeResolvedAst(alloc: std.mem.Allocator, tables: []const resolved_ast.ResolvedTable, views: []const ast_mod.View) !resolved_ast.ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = try allocTables(alloc, tables),
        .views = try allocViews(alloc, views),
        .sql_comments = &.{},
    };
}

// ─── Tests ───────────────────────────────────────────────────────

test "docs: empty schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "# Schema Documentation") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Tables:** 0") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Views:** 0") != null);
}

test "docs: schema with name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = resolved_ast.ResolvedAst{
        .schema_name = "my_app",
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = try docs.generate(alloc, ast);
    try testing.expect(std.mem.indexOf(u8, result, "# my_app Schema Documentation") != null);
}

test "docs: single table with fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{
        makeField("id", .{ .simple = "int" }),
        makeField("name", .{ .simple = "varchar(255)" }),
        makeField("email", .{ .simple = "text" }),
    });
    const table = resolved_ast.ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "### `users`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`id`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`name`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**Total Fields:** 3") != null);
}

test "docs: table with table comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{makeField("id", .{ .simple = "int" })});
    const table = resolved_ast.ResolvedTable{
        .name = "orders",
        .comment = "Customer orders",
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "Customer orders") != null);
}

test "docs: table with field comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{.{
        .name = "status",
        .type_info = .{ .simple = "varchar(20)" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = "order status",
        .line_no = 1,
    }});
    const table = resolved_ast.ResolvedTable{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "order status") != null);
}

test "docs: field with default value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{.{
        .name = "role",
        .type_info = .{ .simple = "varchar(20)" },
        .modifiers = &.{},
        .default_val = .{ .value = "'user'", .line_no = 1 },
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    }});
    const table = resolved_ast.ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "`'user'`") != null);
}

test "docs: field with check constraint" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{.{
        .name = "age",
        .type_info = .{ .simple = "int" },
        .modifiers = &.{},
        .default_val = null,
        .check = .{ .expr = "age >= 0", .kind = .range_both_exclusive, .line_no = 1 },
        .fk = null,
        .comment = null,
        .line_no = 1,
    }});
    const table = resolved_ast.ResolvedTable{
        .name = "people",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "CHECK: age >= 0") != null);
    try testing.expect(std.mem.indexOf(u8, result, "**CHECK Constraints:** 1") != null);
}

test "docs: slot field is skipped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{
        makeField("...", .none),
        makeField("id", .{ .simple = "int" }),
    });
    const table = resolved_ast.ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "| `...` |") == null);
    try testing.expect(std.mem.indexOf(u8, result, "| `id` |") != null);
}

test "docs: view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const views = try allocViews(alloc, &.{.{
        .name = "active_users",
        .query = "SELECT * FROM users WHERE active = 1",
        .comment = null,
        .line_no = 1,
    }});
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{}, views));
    try testing.expect(std.mem.indexOf(u8, result, "### `active_users`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "SELECT * FROM users WHERE active = 1") != null);
}

test "docs: field type variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try allocFields(alloc, &.{
        makeField("f_none", .none),
        makeField("f_simple", .{ .simple = "int" }),
        makeField("f_int_explicit", .{ .int_explicit = 11 }),
        makeField("f_decimal", .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } }),
        makeField("f_varchar_zero", .{ .varchar_explicit = 0 }),
        makeField("f_varchar_n", .{ .varchar_explicit = 100 }),
        makeField("f_raw_sql", .{ .raw_sql = "JSON" }),
    });
    const table = resolved_ast.ResolvedTable{
        .name = "type_test",
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const result = try docs.generate(alloc, try makeResolvedAst(alloc, &.{table}, &.{}));
    try testing.expect(std.mem.indexOf(u8, result, "any") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`int`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "int(11)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "decimal(10,2)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "text") != null);
    try testing.expect(std.mem.indexOf(u8, result, "varchar(100)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`JSON`") != null);
}
