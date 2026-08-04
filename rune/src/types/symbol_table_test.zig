const std = @import("std");
const symbol_table = @import("symbol_table.zig");
const resolved_ast = @import("resolved_ast.zig");
const ast = @import("ast.zig");

const testing = std.testing;
const SymbolTable = symbol_table.SymbolTable;

// ─── Helpers ──────────────────────────────────────────────────

fn makeTestTable(alloc: std.mem.Allocator, name: []const u8, fields: []const ast.Field) !resolved_ast.ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast.Field, fields),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

// ─── registerTable ────────────────────────────────────────────

test "registerTable: basic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const table = try makeTestTable(alloc, "users", &.{});

    try testing.expect(try st.registerTable("users", &table));
    try testing.expectEqual(@as(?*const resolved_ast.ResolvedTable, &table), st.lookupTable("users"));
}

test "registerTable: duplicate name returns false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const t1 = try makeTestTable(alloc, "users", &.{});
    const t2 = try makeTestTable(alloc, "users", &.{});

    try testing.expect(try st.registerTable("users", &t1));
    try testing.expect(!try st.registerTable("users", &t2));
}

// ─── registerTemplate ─────────────────────────────────────────

test "registerTemplate: basic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    try testing.expect(try st.registerTemplate("timestamps"));
    try testing.expect(st.contains("timestamps"));
}

test "registerTemplate: duplicate returns false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    try testing.expect(try st.registerTemplate("timestamps"));
    try testing.expect(!try st.registerTemplate("timestamps"));
}

// ─── Cross-type conflicts ─────────────────────────────────────

test "registerTable: conflicts with template name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    try testing.expect(try st.registerTemplate("base"));

    const table = try makeTestTable(alloc, "base", &.{});
    try testing.expect(!try st.registerTable("base", &table));
}

test "registerTemplate: conflicts with table name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const table = try makeTestTable(alloc, "users", &.{});
    try testing.expect(try st.registerTable("users", &table));

    try testing.expect(!try st.registerTemplate("users"));
}

// ─── lookupTable ──────────────────────────────────────────────

test "lookupTable: returns null for missing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    try testing.expectEqual(@as(?*const resolved_ast.ResolvedTable, null), st.lookupTable("nonexistent"));
}

// ─── lookupField ──────────────────────────────────────────────

test "lookupField: finds existing field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const fields = [_]ast.Field{
        .{ .name = "id", .type_info = .{ .simple = "n" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .{ .name = "email", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 2 },
    };
    const table = try makeTestTable(alloc, "users", &fields);
    try testing.expect(try st.registerTable("users", &table));

    const result = st.lookupField("users", "email");
    try testing.expect(result != null);
    try testing.expectEqualStrings("email", result.?.field.name);
    try testing.expectEqualStrings("users", result.?.table_name);
}

test "lookupField: returns null for missing table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    try testing.expectEqual(@as(?symbol_table.FieldEntry, null), st.lookupField("nonexistent", "id"));
}

test "lookupField: returns null for missing field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const fields = [_]ast.Field{
        .{ .name = "id", .type_info = .{ .simple = "n" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
    };
    const table = try makeTestTable(alloc, "users", &fields);
    try testing.expect(try st.registerTable("users", &table));

    try testing.expectEqual(@as(?symbol_table.FieldEntry, null), st.lookupField("users", "name"));
}

// ─── contains ─────────────────────────────────────────────────

test "contains: table and template" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var st = SymbolTable.init(alloc);
    const table = try makeTestTable(alloc, "users", &.{});
    try testing.expect(try st.registerTable("users", &table));
    try testing.expect(try st.registerTemplate("timestamps"));

    try testing.expect(st.contains("users"));
    try testing.expect(st.contains("timestamps"));
    try testing.expect(!st.contains("nonexistent"));
}
