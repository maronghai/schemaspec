const std = @import("std");
const fk = @import("fk.zig");
const sp = @import("../parser/sql_parser.zig");

const testing = std.testing;

test "classifyFk shorthand single->id" {
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"user_id"},
        .ref_table = "user",
        .ref_fields = &.{"id"},
        .actions = &.{},
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqual(fk.FkForm.shorthand, result.form);
    try testing.expect(result.text != null);
    try testing.expectEqualStrings("> user_id user.id", result.text.?);
}

test "classifyFk full multi-field" {
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{ "a_id", "b_id" },
        .ref_table = "ab",
        .ref_fields = &.{ "a", "b" },
        .actions = &.{},
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqual(fk.FkForm.full, result.form);
}

test "classifyFk full with actions" {
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"order_id"},
        .ref_table = "orders",
        .ref_fields = &.{"id"},
        .actions = &.{
            .{ .trigger = .on_delete, .action = .cascade },
        },
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqual(fk.FkForm.full, result.form);
    try testing.expect(result.text != null);
    try testing.expectEqualStrings("> order_id orders(id) -C", result.text.?);
}

test "classifyFk full with multiple actions" {
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"order_id"},
        .ref_table = "orders",
        .ref_fields = &.{"id"},
        .actions = &.{
            .{ .trigger = .on_delete, .action = .cascade },
            .{ .trigger = .on_update, .action = .set_null },
        },
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqual(fk.FkForm.full, result.form);
    try testing.expect(result.text != null);
    try testing.expectEqualStrings("> order_id orders(id) -C N", result.text.?);
}

test "classifyFk shorthand with non-id reference" {
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"email"},
        .ref_table = "auth",
        .ref_fields = &.{"email"},
        .actions = &.{},
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqual(fk.FkForm.full, result.form);
    try testing.expect(result.text != null);
    try testing.expectEqualStrings("> email auth(email)", result.text.?);
}

// ─── v0.332.0: inline column-level FK round-trip ────────────

test "classifyFk omits empty reference column list" {
    // `a_id INT REFERENCES a` — no explicit column list; output must not
    // render empty parentheses.
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"a_id"},
        .ref_table = "a",
        .ref_fields = &.{},
        .actions = &.{},
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqualStrings("> (a_id) a", result.text orelse "");
}

test "classifyFk drops default-severity actions" {
    // RESTRICT / NO ACTION are the .ss omission default — no token emitted.
    const alloc = testing.allocator;
    const fk_data = sp.SqlForeignKey{
        .fields = &.{"z"},
        .ref_table = "c",
        .ref_fields = &.{"x"},
        .actions = &.{
            .{ .trigger = .on_delete, .action = .no_action },
            .{ .trigger = .on_update, .action = .restrict },
        },
    };
    const result = fk.classifyFk(alloc, fk_data);
    defer if (result.text) |t| alloc.free(t);
    try testing.expectEqualStrings("> z c(x)", result.text orelse "");
}
