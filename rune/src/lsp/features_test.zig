const std = @import("std");
const testing = std.testing;
const features = @import("features.zig");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const TypedTable = @import("../types/typed_ast.zig").TypedTable;
const TypedColumn = @import("../types/typed_ast.zig").TypedColumn;
const TypedView = @import("../types/typed_ast.zig").TypedView;
const ColumnFlags = @import("../types/typed_ast.zig").ColumnFlags;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const sql_type_mod = @import("../types/sql_type.zig");
const ast_mod = @import("../types/ast.zig");
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── Shared Test Helpers ───────────────────────────────────────

fn makeColumn(name: []const u8, sql_type: sql_type_mod.SqlType, flags: ColumnFlags) TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type,
        .flags = flags,
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 2,
    };
}

fn makePkColumn(name: []const u8) TypedColumn {
    return makeColumn(name, .int, .{ .primary_key = true, .auto_increment = true });
}

fn makeSimpleColumn(name: []const u8) TypedColumn {
    return makeColumn(name, .{ .varchar = 255 }, .{});
}

fn makeTable(name: []const u8, columns: []const TypedColumn) TypedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .columns = columns,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

fn makeTableWithComment(name: []const u8, comment: []const u8, columns: []const TypedColumn) TypedTable {
    return .{
        .name = name,
        .comment = comment,
        .engine = null,
        .columns = columns,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

fn makeTableWithFks(name: []const u8, columns: []const TypedColumn, fks: []const ast_mod.FkDecl) TypedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .columns = columns,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    };
}

fn makeView(name: []const u8) TypedView {
    return .{
        .name = name,
        .query = "SELECT 1",
        .comment = null,
        .line_no = 10,
    };
}

fn makeAst(tables: []const TypedTable, views: []const TypedView) TypedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = views,
        .sql_comments = &.{},
    };
}

// ─── Document Symbols Tests ────────────────────────────────────

test "getDocumentSymbols: single table with columns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTable("users", &.{
        makePkColumn("id"),
        makeSimpleColumn("name"),
    });
    const ast = makeAst(&.{table}, &.{});
    const symbols = features.getDocumentSymbols(alloc, ast);

    try testing.expectEqual(@as(usize, 1), symbols.len);
    try testing.expectEqualStrings("users", symbols[0].name);
    try testing.expect(symbols[0].children != null);
    try testing.expectEqual(@as(usize, 2), symbols[0].children.?.len);
}

test "getDocumentSymbols: multiple tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tables = &.{
        makeTable("users", &.{makePkColumn("id")}),
        makeTable("orders", &.{makePkColumn("id")}),
    };
    const ast = makeAst(tables, &.{});
    const symbols = features.getDocumentSymbols(alloc, ast);

    try testing.expectEqual(@as(usize, 2), symbols.len);
}

test "getDocumentSymbols: table with view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTable("users", &.{makePkColumn("id")});
    const view = makeView("user_summary");
    const ast = makeAst(&.{table}, &.{view});
    const symbols = features.getDocumentSymbols(alloc, ast);

    try testing.expectEqual(@as(usize, 2), symbols.len);
    try testing.expectEqualStrings("user_summary", symbols[1].name);
}

// ─── Hover Tests ───────────────────────────────────────────────

test "getHover: table header" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTableWithComment("users", "User accounts", &.{
        makePkColumn("id"),
        makeSimpleColumn("name"),
    });
    const ast = makeAst(&.{table}, &.{});
    const hover = features.getHover(alloc, ast, .{ .line = 0, .character = 0 }, .mysql);

    try testing.expect(hover != null);
    try testing.expect(hover.?.contents.value.len > 0);
    try testing.expect(std.mem.indexOf(u8, hover.?.contents.value, "users") != null);
    try testing.expect(std.mem.indexOf(u8, hover.?.contents.value, "User accounts") != null);
}

test "getHover: column line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create columns with explicit line numbers
    var col_id = makeColumn("id", .int, .{ .primary_key = true, .auto_increment = true });
    col_id.line_no = 2; // col_line = 2 - 1 = 1
    var col_name = makeColumn("name", .{ .varchar = 255 }, .{});
    col_name.line_no = 3; // col_line = 3 - 1 = 2

    const table = makeTable("users", &.{ col_id, col_name });
    const ast = makeAst(&.{table}, &.{});
    // Hover on line 2 (0-indexed) should show "name" column
    const hover = features.getHover(alloc, ast, .{ .line = 2, .character = 0 }, .mysql);

    try testing.expect(hover != null);
    try testing.expect(std.mem.indexOf(u8, hover.?.contents.value, "name") != null);
}

test "getHover: no match returns null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTable("users", &.{makePkColumn("id")});
    const ast = makeAst(&.{table}, &.{});
    // Line 100 doesn't exist
    const hover = features.getHover(alloc, ast, .{ .line = 100, .character = 0 }, .mysql);

    try testing.expect(hover == null);
}

// ─── Completion Tests ──────────────────────────────────────────

test "getCompletions: returns keywords" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = makeAst(&.{}, &.{});
    // Cursor at empty line (top level context)
    const text = "\ntable users {\n}";
    const result = features.getCompletions(alloc, ast, .{ .line = 0, .character = 0 }, text);

    try testing.expect(result.is_incomplete == false);
    try testing.expect(result.items.len > 0);
    // Check that "table" keyword is present
    var found_table = false;
    for (result.items) |item| {
        if (std.mem.eql(u8, item.label, "table")) {
            found_table = true;
            break;
        }
    }
    try testing.expect(found_table);
}

test "getCompletions: type symbols at column position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = makeAst(&.{}, &.{});
    // Cursor inside table body (after opening brace)
    const text = "table users {\n  name \n}";
    const result = features.getCompletions(alloc, ast, .{ .line = 1, .character = 7 }, text);

    try testing.expect(result.items.len > 0);
    // Check that "s" (varchar) type is present
    var found_s = false;
    for (result.items) |item| {
        if (std.mem.eql(u8, item.label, "s")) {
            found_s = true;
            break;
        }
    }
    try testing.expect(found_s);
}

// ─── Go-to-Definition Tests ────────────────────────────────────

test "getDefinition: FK reference returns target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fk = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 2,
    };

    var table = makeTableWithFks("orders", &.{
        makePkColumn("id"),
        makeColumn("user_id", .int, .{}),
    }, &.{fk});
    table.line_no = 1;

    var users_table = makeTable("users", &.{makePkColumn("id")});
    users_table.line_no = 5;

    const ast = makeAst(&.{ table, users_table }, &.{});

    // Cursor on the FK reference line (line 1, which is 0-indexed line 1 = line_no 2 - 1)
    const def = features.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 1, .character = 0 });

    try testing.expect(def != null);
    // The definition should point to the users table
    try testing.expect(std.mem.indexOf(u8, def.?.uri, "test.ss") != null);
}

// ─── References Tests ──────────────────────────────────────────

test "getReferences: find table references" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTable("users", &.{makePkColumn("id")});
    const ast = makeAst(&.{table}, &.{});

    const refs = features.getReferences(alloc, ast, 0, 6, "file:///test.ss", "# users\nid n++");

    try testing.expect(refs.len > 0);
}

// ─── Highlights Tests ──────────────────────────────────────────

test "getDocumentHighlights: table name highlights" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = makeTable("users", &.{makePkColumn("id")});
    const ast = makeAst(&.{table}, &.{});

    const highlights = features.getDocumentHighlights(alloc, ast, 0, 6, "# users\nid n++");

    try testing.expect(highlights.len > 0);
}

// ─── FK-Related Tests ────────────────────────────────────────

test "getReferences: FK column reference finds precise range" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fk = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 4,
    };

    var orders_table = makeTableWithFks("orders", &.{
        makePkColumn("id"),
        makeColumn("user_id", .int, .{}),
    }, &.{fk});
    orders_table.line_no = 3;

    var users_table = makeTable("users", &.{makePkColumn("id")});
    users_table.line_no = 1;

    const ast = makeAst(&.{ users_table, orders_table }, &.{});
    // Document text: line 0 = "# users", line 1 = "id n++ PK", line 2 = "", line 3 = "# orders", line 4 = "user_id n -> users.id"
    const doc_text = "# users\nid n++ PK\n\n# orders\nuser_id n -> users.id";

    // Cursor on "users" table name (line 0, character 2)
    const refs = features.getReferences(alloc, ast, 0, 2, "file:///test.ss", doc_text);

    // Should find at least 1 reference (the FK usage in orders)
    try testing.expect(refs.len >= 1);
}

test "getDocumentHighlights: FK column highlights precise range" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fk = ast_mod.FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 4,
    };

    var orders_table = makeTableWithFks("orders", &.{
        makePkColumn("id"),
        makeColumn("user_id", .int, .{}),
    }, &.{fk});
    orders_table.line_no = 3;

    var users_table = makeTable("users", &.{makePkColumn("id")});
    users_table.line_no = 1;

    const ast = makeAst(&.{ users_table, orders_table }, &.{});
    const doc_text = "# users\nid n++ PK\n\n# orders\nuser_id n -> users.id";

    // Cursor on "users" table name (line 0, character 2)
    const highlights = features.getDocumentHighlights(alloc, ast, 0, 2, doc_text);

    // Should find at least 1 highlight (the FK usage)
    try testing.expect(highlights.len >= 1);
    // The FK highlight should NOT be a full-line range
    for (highlights) |hl| {
        if (hl.kind == .read) {
            // FK reference should have a precise range (not starting at character 0 with full line width)
            try testing.expect(hl.range.end.character > hl.range.start.character);
            try testing.expect(hl.range.end.character - hl.range.start.character < 50); // Not a full line
        }
    }
}

test "getDefinition: multi-column FK navigates to target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Multi-column FK: (user_id, role_id) -> (users.id, users.id)
    const fk = ast_mod.FkDecl{
        .fields = &.{ "user_id", "role_id" },
        .ref_table = "users",
        .ref_fields = &.{ "id", "id" },
        .actions = &.{},
        .line_no = 2, // FK declaration on line_no 2 (0-indexed: line 1)
    };

    var user_roles_table = makeTableWithFks("user_roles", &.{
        makePkColumn("id"),
        makeColumn("user_id", .int, .{}),
        makeColumn("role_id", .int, .{}),
    }, &.{fk});
    user_roles_table.line_no = 1;

    var users_table = makeTable("users", &.{makePkColumn("id")});
    users_table.line_no = 5;

    const ast = makeAst(&.{ user_roles_table, users_table }, &.{});

    // Cursor on FK declaration line (line 1, which is 0-indexed from line_no 2 - 1)
    const def = features.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 1, .character = 0 });

    // Should navigate to the users table
    try testing.expect(def != null);
    try testing.expect(std.mem.indexOf(u8, def.?.uri, "test.ss") != null);
}

test "getHover: column with dialect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var col_id = makeColumn("id", .int, .{ .primary_key = true, .auto_increment = true });
    col_id.line_no = 2;

    const table = makeTable("users", &.{col_id});
    const ast = makeAst(&.{table}, &.{});

    // Test with MySQL dialect
    const hover_mysql = features.getHover(alloc, ast, .{ .line = 1, .character = 0 }, .mysql);
    try testing.expect(hover_mysql != null);
    if (hover_mysql) |h| {
        defer alloc.free(h.contents.value);
        try testing.expect(std.mem.indexOf(u8, h.contents.value, "id") != null);
    }

    // Test with PostgreSQL dialect
    const hover_pg = features.getHover(alloc, ast, .{ .line = 1, .character = 0 }, .pg);
    try testing.expect(hover_pg != null);
    if (hover_pg) |h| {
        defer alloc.free(h.contents.value);
        try testing.expect(std.mem.indexOf(u8, h.contents.value, "id") != null);
    }
}
