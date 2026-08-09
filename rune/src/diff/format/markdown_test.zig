const std = @import("std");
const testing = std.testing;
const diff_types = @import("../../diff/types.zig");
const markdown = @import("markdown.zig");
const dialect_mod = @import("../../dialect/dialect.zig");

test "markdown format: empty diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const empty_diff = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, empty_diff, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "## Schema Diff") != null);
    try testing.expect(std.mem.indexOf(u8, result, "| Tables added | 0 |") != null);
    try testing.expect(std.mem.indexOf(u8, result, "| Tables dropped | 0 |") != null);
}

test "markdown format: dropped table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var dropped_buf: [1][]const u8 = undefined;
    dropped_buf[0] = "old_table";

    const d = diff_types.SchemaDiff{
        .dropped_tables = &dropped_buf,
        .table_diffs = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, d, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "old_table") != null);
    try testing.expect(std.mem.indexOf(u8, result, "| Tables dropped | 1 |") != null);
}

test "markdown format: creates table with field add" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const field = diff_types.FieldDiff{
        .name = "email",
        .action = .add,
        .old_field = null,
        .new_field = null,
        .rename_from = null,
    };

    const td = diff_types.TableDiff{
        .name = "contacts",
        .action = .create,
        .field_diffs = &.{field},
        .index_diffs = &.{},
        .fk_diffs = &.{},
    };

    const d = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, d, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "### + Table `contacts`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "+ `email`") != null);
}

test "markdown format: multiple dropped tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var dropped_buf: [2][]const u8 = undefined;
    dropped_buf[0] = "users";
    dropped_buf[1] = "posts";

    const d = diff_types.SchemaDiff{
        .dropped_tables = &dropped_buf,
        .table_diffs = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, d, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "| Tables dropped | 2 |") != null);
    try testing.expect(std.mem.indexOf(u8, result, "users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "posts") != null);
}

test "markdown format: altered table with field modify" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const field = diff_types.FieldDiff{
        .name = "status",
        .action = .modify,
        .old_field = .{ .name = "status", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 0 },
        .new_field = .{ .name = "status", .type_info = .{ .simple = "S" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 0 },
        .rename_from = null,
    };

    const td = diff_types.TableDiff{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{field},
        .index_diffs = &.{},
        .fk_diffs = &.{},
    };

    const d = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{td},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, d, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "### ~ Table `users`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "`status`") != null);
    try testing.expect(std.mem.indexOf(u8, result, "→") != null);
}

test "markdown format: view diff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const vd = diff_types.ViewDiff{
        .name = "active_users",
        .action = .create,
    };

    const d = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .table_diffs = &.{},
        .view_diffs = &.{vd},
        .custom_type_diffs = &.{},
    };

    const result = try markdown.formatDiffMarkdown(alloc, d, .mysql);
    try testing.expect(std.mem.indexOf(u8, result, "active_users") != null);
    try testing.expect(std.mem.indexOf(u8, result, "View") != null);
}
