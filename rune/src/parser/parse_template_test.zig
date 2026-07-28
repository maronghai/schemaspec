const std = @import("std");
const parse_template = @import("parse_template.zig");
const ast_mod = @import("../types/ast.zig");

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
