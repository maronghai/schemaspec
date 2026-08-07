const std = @import("std");
const handlers = @import("handlers.zig");
const forward = @import("forward.zig");

const testing = std.testing;

test "formatValidateResult: valid schema produces correct JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const s = forward.Stats{
        .tables = 3,
        .fields = 10,
        .views = 1,
        .not_null_fields = 5,
        .numeric_fields = 4,
        .string_fields = 3,
        .datetime_fields = 2,
        .boolean_fields = 1,
        .other_fields = 0,
        .foreign_keys = 2,
        .indexes = 3,
        .check_constraints = 1,
        .custom_types = 0,
    };
    const json = try handlers.formatValidateResult(alloc, true, s, 0);
    try testing.expect(std.mem.indexOf(u8, json, "\"valid\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"errors\":0") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"tables\":3") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"fields\":10") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"views\":1") != null);
}

test "formatValidateResult: invalid schema produces correct JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const s = forward.Stats{
        .tables = 0,
        .fields = 0,
        .views = 0,
        .not_null_fields = 0,
        .numeric_fields = 0,
        .string_fields = 0,
        .datetime_fields = 0,
        .boolean_fields = 0,
        .other_fields = 0,
        .foreign_keys = 0,
        .indexes = 0,
        .check_constraints = 0,
        .custom_types = 0,
    };
    const json = try handlers.formatValidateResult(alloc, false, s, 5);
    try testing.expect(std.mem.indexOf(u8, json, "\"valid\":false") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"errors\":5") != null);
}
