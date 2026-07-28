const std = @import("std");
const js = @import("json_schema.zig");
const typed_ast = @import("types/typed_ast.zig");

const testing = std.testing;
const test_helpers = @import("semantic/test_helpers.zig");
const makeTestColumn = test_helpers.makeTestColumn;

test "json_schema: int column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("id", .int);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"integer\"}", result);
}

test "json_schema: varchar column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("name", .{ .varchar = 64 });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"string\",\"maxLength\":64}", result);
}

test "json_schema: boolean column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("active", .boolean);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"boolean\"}", result);
}

test "json_schema: enum column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const vals = try alloc.dupe([]const u8, &.{ "active", "inactive", "banned" });
    const col = makeTestColumn("status", .{ .enum_values = vals });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expect(std.mem.indexOf(u8, result, "\"enum\":[\"active\",\"inactive\",\"banned\"]") != null);
}

test "json_schema: decimal column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("price", .{ .decimal = .{ .precision = 10, .scale = 2 } });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"number\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"multipleOf\"") != null);
}
