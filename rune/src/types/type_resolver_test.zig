const std = @import("std");
const type_resolver = @import("type_resolver.zig");
const test_helpers = @import("../semantic/test_helpers.zig");
const ast_mod = @import("../types/ast.zig");
const Field = ast_mod.Field;

const testing = std.testing;

test "classifyModifiers: empty modifiers — all false" {
    const field = test_helpers.makeTestField("x", .{ .simple = "n" });
    const flags = type_resolver.classifyModifiers(field);
    try testing.expect(!flags.pk);
    try testing.expect(!flags.ai);
    try testing.expect(!flags.nullable_mod);
    try testing.expect(!flags.unsigned);
    try testing.expect(!flags.inline_unique);
    try testing.expect(!flags.inline_index);
}

test "classifyModifiers: primary_key + nullable" {
    var field = test_helpers.makeTestField("id", .{ .simple = "n" });
    field.modifiers = &.{ .{ .kind = .primary_key, .line_no = 1 }, .{ .kind = .nullable, .line_no = 1 } };
    const flags = type_resolver.classifyModifiers(field);
    try testing.expect(flags.pk);
    try testing.expect(flags.nullable_mod);
    try testing.expect(!flags.ai);
    try testing.expect(!flags.unsigned);
}

test "classifyModifiers: auto_inc_pk on numeric — pk + ai" {
    var field = test_helpers.makeTestField("id", .{ .simple = "n" });
    field.modifiers = &.{.{ .kind = .auto_inc_pk, .line_no = 1 }};
    const flags = type_resolver.classifyModifiers(field);
    try testing.expect(flags.pk);
    try testing.expect(flags.ai);
    try testing.expect(!flags.on_update_ts);
}

test "classifyModifiers: auto_inc_pk on datetime — on_update_ts" {
    var field = test_helpers.makeTestField("updated_at", .{ .simple = "t" });
    field.modifiers = &.{.{ .kind = .auto_inc_pk, .line_no = 1 }};
    const flags = type_resolver.classifyModifiers(field);
    try testing.expect(!flags.pk);
    try testing.expect(!flags.ai);
    try testing.expect(flags.on_update_ts);
    try testing.expect(flags.has_timestamp_mod);
}

test "buildSymType: simple single-char type" {
    const result = try type_resolver.buildSymType(testing.allocator, .{ .simple = "n" }, false);
    try testing.expect(result != null);
    try testing.expectEqualStrings("n", result.?);
}

test "buildSymType: unsigned int gets + prefix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try type_resolver.buildSymType(arena.allocator(), .{ .simple = "n" }, true);
    try testing.expect(result != null);
    try testing.expectEqualStrings("+n", result.?);
}

test "buildSymType: unsigned N (bigint) gets + prefix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try type_resolver.buildSymType(arena.allocator(), .{ .simple = "N" }, true);
    try testing.expect(result != null);
    try testing.expectEqualStrings("+N", result.?);
}

test "buildSymType: varchar_explicit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try type_resolver.buildSymType(arena.allocator(), .{ .varchar_explicit = 255 }, false);
    try testing.expect(result != null);
    try testing.expectEqualStrings("s255", result.?);
}

test "buildSymType: decimal_explicit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try type_resolver.buildSymType(arena.allocator(), .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } }, false);
    try testing.expect(result != null);
    try testing.expectEqualStrings("10,2", result.?);
}

test "buildSymType: none → s" {
    const result = try type_resolver.buildSymType(testing.allocator, .none, false);
    try testing.expect(result != null);
    try testing.expectEqualStrings("s", result.?);
}
