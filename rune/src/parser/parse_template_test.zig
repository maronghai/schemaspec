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
    const alloc = testing.allocator;
    const line = tk.Line{
        .tokens = &.{ "%", "base" },
        .line_no = 1,
        .indent = 0,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    defer {
        if (header.name) |n| alloc.free(n);
        for (header.parents) |p| alloc.free(p);
        alloc.free(header.parents.ptr[0..4]);
    }
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("base", header.name.?);
    try testing.expectEqual(@as(usize, 0), header.parents.len);
}

test "parseTemplateHeader: template with parent" {
    const alloc = testing.allocator;
    const line = tk.Line{
        .tokens = &.{ "%", "user", ">", "base" },
        .line_no = 5,
        .indent = 0,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    defer {
        if (header.name) |n| alloc.free(n);
        for (header.parents) |p| alloc.free(p);
        alloc.free(header.parents.ptr[0..4]);
    }
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("user", header.name.?);
    try testing.expectEqual(@as(usize, 1), header.parents.len);
    try testing.expectEqualStrings("base", header.parents[0]);
}

test "parseTemplateHeader: mixin syntax" {
    const alloc = testing.allocator;
    const line = tk.Line{
        .tokens = &.{ "%", "user", "+", "timestamp" },
        .line_no = 10,
        .indent = 0,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    defer {
        if (header.name) |n| alloc.free(n);
        for (header.parents) |p| alloc.free(p);
        alloc.free(header.parents.ptr[0..4]);
    }
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("user", header.name.?);
    try testing.expectEqual(@as(usize, 1), header.parents.len);
    try testing.expectEqualStrings("timestamp", header.parents[0]);
}

test "parseTemplateHeader: anonymous template" {
    const alloc = testing.allocator;
    const line = tk.Line{
        .tokens = &.{ "%" },
        .line_no = 1,
        .indent = 0,
    };
    const header = try parse_template.parseTemplateHeader(alloc, line);
    defer {
        if (header.name) |n| alloc.free(n);
        for (header.parents) |p| alloc.free(p);
        alloc.free(header.parents.ptr[0..4]);
    }
    try testing.expect(header.name == null);
    try testing.expectEqual(@as(usize, 0), header.parents.len);
}
