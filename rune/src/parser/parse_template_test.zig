const std = @import("std");
const parse_template = @import("parse_template.zig");
const ast_mod = @import("../types/ast.zig");
const tk = @import("tokenizer.zig");

const testing = std.testing;
const Field = ast_mod.Field;
const findSlot = parse_template.findSlot;

test "findSlot: present" {
    const fields = [_]Field{
        .{ .name = "a", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .{ .name = "...", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 2 },
        .{ .name = "b", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 3 },
    };
    try testing.expectEqual(@as(?usize, 1), findSlot(&fields));
}

test "findSlot: absent" {
    const fields = [_]Field{
        .{ .name = "a", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
    };
    try testing.expectEqual(@as(?usize, null), findSlot(&fields));
}

test "findSlot: empty fields" {
    const fields = [_]Field{};
    try testing.expectEqual(@as(?usize, null), findSlot(&fields));
}

test "findSlot: slot at beginning" {
    const fields = [_]Field{
        .{ .name = "...", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .{ .name = "a", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 2 },
    };
    try testing.expectEqual(@as(?usize, 0), findSlot(&fields));
}

test "findSlot: slot at end" {
    const fields = [_]Field{
        .{ .name = "a", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .{ .name = "b", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 2 },
        .{ .name = "...", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 3 },
    };
    try testing.expectEqual(@as(?usize, 2), findSlot(&fields));
}

test "parseTemplateHeader: simple template" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "base" },
        .raw = "% base",
        .trimmed = "% base",
        .line_no = 1,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("base", header.name.?);
    try testing.expectEqual(@as(usize, 0), header.parents.len);
}

test "parseTemplateHeader: template with parent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "user", ">", "base" },
        .raw = "% user > base",
        .trimmed = "% user > base",
        .line_no = 5,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("user", header.name.?);
    try testing.expectEqual(@as(usize, 1), header.parents.len);
    try testing.expectEqualStrings("base", header.parents[0]);
}

test "parseTemplateHeader: mixin syntax" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "user", "+", "timestamp" },
        .raw = "% user + timestamp",
        .trimmed = "% user + timestamp",
        .line_no = 10,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("user", header.name.?);
    try testing.expectEqual(@as(usize, 1), header.parents.len);
    try testing.expectEqualStrings("timestamp", header.parents[0]);
}

test "parseTemplateHeader: anonymous template" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%" },
        .raw = "%",
        .trimmed = "%",
        .line_no = 1,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name == null);
    try testing.expectEqual(@as(usize, 0), header.parents.len);
}
