const std = @import("std");
const testing = std.testing;
const utils = @import("utils.zig");

test "optionalStrEq: both null" {
    try testing.expect(utils.optionalStrEq(null, null));
}

test "optionalStrEq: first null" {
    try testing.expect(!utils.optionalStrEq(null, "hello"));
}

test "optionalStrEq: second null" {
    try testing.expect(!utils.optionalStrEq("hello", null));
}

test "optionalStrEq: equal strings" {
    try testing.expect(utils.optionalStrEq("hello", "hello"));
}

test "optionalStrEq: different strings" {
    try testing.expect(!utils.optionalStrEq("hello", "world"));
}

test "optionalStrEq: empty strings" {
    try testing.expect(utils.optionalStrEq("", ""));
}

test "jsonEscapeString: no escapes needed" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "hello world");
    try testing.expectEqualStrings("hello world", aw.written());
}

test "jsonEscapeString: double quote" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "say \"hi\"");
    try testing.expectEqualStrings("say \\\"hi\\\"", aw.written());
}

test "jsonEscapeString: backslash" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "path\\to");
    try testing.expectEqualStrings("path\\\\to", aw.written());
}

test "jsonEscapeString: newline" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "line1\nline2");
    try testing.expectEqualStrings("line1\\nline2", aw.written());
}

test "jsonEscapeString: tab" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "col1\tcol2");
    try testing.expectEqualStrings("col1\\tcol2", aw.written());
}

test "jsonEscapeString: control character" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "a\x01b");
    try testing.expectEqualStrings("a\\u0001b", aw.written());
}

test "jsonEscapeString: empty string" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try utils.jsonEscapeString(&aw.writer, "");
    try testing.expectEqualStrings("", aw.written());
}
