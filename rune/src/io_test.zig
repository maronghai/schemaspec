const std = @import("std");
const testing = std.testing;

// ─── utils.zig Unit Tests ─────────────────────────────────────

const utils = @import("utils.zig");

// ─── optionalStrEq ────────────────────────────────────────────

test "optionalStrEq: both null" {
    try testing.expect(utils.optionalStrEq(null, null));
}

test "optionalStrEq: first null" {
    try testing.expect(!utils.optionalStrEq(null, "abc"));
}

test "optionalStrEq: second null" {
    try testing.expect(!utils.optionalStrEq("abc", null));
}

test "optionalStrEq: both equal" {
    try testing.expect(utils.optionalStrEq("hello", "hello"));
}

test "optionalStrEq: both different" {
    try testing.expect(!utils.optionalStrEq("abc", "xyz"));
}

test "optionalStrEq: empty strings" {
    try testing.expect(utils.optionalStrEq("", ""));
}

test "optionalStrEq: empty vs non-empty" {
    try testing.expect(!utils.optionalStrEq("", "abc"));
}

test "optionalStrEq: case sensitive" {
    try testing.expect(!utils.optionalStrEq("abc", "ABC"));
}

// ─── jsonEscapeString ─────────────────────────────────────────

test "jsonEscapeString: plain text" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "hello world");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("hello world", result);
}

test "jsonEscapeString: empty string" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("", result);
}

test "jsonEscapeString: double quote" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "say \"hi\"");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("say \\\"hi\\\"", result);
}

test "jsonEscapeString: backslash" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "path\\to\\file");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("path\\\\to\\\\file", result);
}

test "jsonEscapeString: newline" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "line1\nline2");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("line1\\nline2", result);
}

test "jsonEscapeString: carriage return" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "a\rb");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a\\rb", result);
}

test "jsonEscapeString: tab" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "col\tval");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("col\\tval", result);
}

test "jsonEscapeString: control character < 0x20" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "\x01");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\\u0001", result);
}

test "jsonEscapeString: mixed escapes" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "a\"b\\c\nd");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a\\\"b\\\\c\\nd", result);
}
