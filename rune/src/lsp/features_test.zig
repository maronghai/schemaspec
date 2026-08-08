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
    const hover = features.getHover(alloc, ast, .{ .line = 0, .character = 0 });

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
    const hover = features.getHover(alloc, ast, .{ .line = 2, .character = 0 });

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
    const hover = features.getHover(alloc, ast, .{ .line = 100, .character = 0 });

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
    _ = alloc;

    const table = makeTable("users", &.{makePkColumn("id")});
    const ast = makeAst(&.{table}, &.{});

    const refs = features.getReferences(ast, 0, 6, "file:///test.ss");

    try testing.expect(refs.len > 0);
}

// ─── Highlights Tests ──────────────────────────────────────────

test "getDocumentHighlights: table name highlights" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    _ = alloc;

    const table = makeTable("users", &.{makePkColumn("id")});
    const ast = makeAst(&.{table}, &.{});

    const highlights = features.getDocumentHighlights(ast, 0, 6);

    try testing.expect(highlights.len > 0);
}
