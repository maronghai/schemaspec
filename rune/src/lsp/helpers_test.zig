const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

test "lineNoToZeroBased - 1-based to 0-based" {
    try testing.expectEqual(@as(u32, 0), helpers.lineNoToZeroBased(@as(u32, 1)));
    try testing.expectEqual(@as(u32, 1), helpers.lineNoToZeroBased(@as(u32, 2)));
    try testing.expectEqual(@as(u32, 99), helpers.lineNoToZeroBased(@as(u32, 100)));
}

test "lineNoToZeroBased - zero returns zero" {
    try testing.expectEqual(@as(u32, 0), helpers.lineNoToZeroBased(@as(u32, 0)));
}

test "makeRange - creates range" {
    const r = helpers.makeRange(1, 2, 3, 4);
    try testing.expectEqual(@as(u32, 1), r.start.line);
    try testing.expectEqual(@as(u32, 2), r.start.character);
    try testing.expectEqual(@as(u32, 3), r.end.line);
    try testing.expectEqual(@as(u32, 4), r.end.character);
}

test "getLineText - first line" {
    const text = "line1\nline2\nline3";
    const line = helpers.getLineText(text, 0);
    try testing.expectEqualStrings("line1", line);
}

test "getLineText - middle line" {
    const text = "line1\nline2\nline3";
    const line = helpers.getLineText(text, 1);
    try testing.expectEqualStrings("line2", line);
}

test "getLineText - last line" {
    const text = "line1\nline2\nline3";
    const line = helpers.getLineText(text, 2);
    try testing.expectEqualStrings("line3", line);
}

test "getLineText - out of range returns empty" {
    const text = "line1\nline2";
    const line = helpers.getLineText(text, 5);
    try testing.expectEqualStrings("", line);
}

test "getLineText - single line no newline" {
    const text = "hello";
    const line = helpers.getLineText(text, 0);
    try testing.expectEqualStrings("hello", line);
}

test "getLineText - empty string" {
    const text = "";
    const line = helpers.getLineText(text, 0);
    try testing.expectEqualStrings("", line);
}

test "lineLength - counts characters" {
    const text = "line1\nline2\nline3";
    try testing.expectEqual(@as(u32, 5), helpers.lineLength(text, 0));
    try testing.expectEqual(@as(u32, 5), helpers.lineLength(text, 1));
    try testing.expectEqual(@as(u32, 5), helpers.lineLength(text, 2));
}

test "wordAtPosition - finds word" {
    const text = "table users {\n  id n ++ PK\n}";
    const word = helpers.wordAtPosition(text, 1, 2);
    try testing.expect(word != null);
    try testing.expectEqualStrings("id", word.?);
}

test "wordAtPosition - finds word at end of line" {
    const text = "table users {\n  id n ++ PK\n}";
    const word = helpers.wordAtPosition(text, 1, 10);
    try testing.expect(word != null);
    try testing.expectEqualStrings("PK", word.?);
}

test "wordAtPosition - returns null for space" {
    const text = "table users {\n  id n ++ PK\n}";
    const word = helpers.wordAtPosition(text, 1, 0);
    try testing.expect(word == null);
}

test "wordAtPosition - out of bounds returns null" {
    const text = "line1";
    const word = helpers.wordAtPosition(text, 5, 0);
    try testing.expect(word == null);
}

test "findNameInLine - finds name" {
    const text = "table users {\n  id n ++ PK\n}";
    const range = helpers.findNameInLine(text, 1, "id");
    try testing.expect(range != null);
    try testing.expectEqual(@as(u32, 1), range.?.start.line);
    try testing.expectEqual(@as(u32, 2), range.?.start.character);
    try testing.expectEqual(@as(u32, 4), range.?.end.character);
}

test "findNameInLine - returns null for missing name" {
    const text = "table users {\n  id n ++ PK\n}";
    const range = helpers.findNameInLine(text, 1, "missing");
    try testing.expect(range == null);
}

test "findNameInLine - returns null for partial match" {
    const text = "table users {\n  id n ++ PK\n}";
    const range = helpers.findNameInLine(text, 1, "i");
    try testing.expect(range == null);
}

test "formatFlagsForHover - primary key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = helpers.formatFlagsForHover(alloc, .{
        .primary_key = true,
        .auto_increment = true,
        .nullable = false,
        .unsigned = false,
        .inline_unique = false,
        .inline_index = false,
        .is_enum = false,
        .is_virtual = false,
        .is_stored = false,
    });
    try testing.expect(std.mem.indexOf(u8, result, "PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, result, "AUTO_INCREMENT") != null);
}

test "formatFlagsForHover - nullable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = helpers.formatFlagsForHover(alloc, .{
        .primary_key = false,
        .auto_increment = false,
        .nullable = true,
        .unsigned = false,
        .inline_unique = false,
        .inline_index = false,
        .is_enum = false,
        .is_virtual = false,
        .is_stored = false,
    });
    try testing.expect(std.mem.indexOf(u8, result, "NULL") != null);
}

test "formatFlagsForHover - empty flags" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = helpers.formatFlagsForHover(alloc, .{
        .primary_key = false,
        .auto_increment = false,
        .nullable = false,
        .unsigned = false,
        .inline_unique = false,
        .inline_index = false,
        .is_enum = false,
        .is_virtual = false,
        .is_stored = false,
    });
    try testing.expectEqual(@as(usize, 0), result.len);
}
