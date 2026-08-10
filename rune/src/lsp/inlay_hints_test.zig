const std = @import("std");
const testing = std.testing;
const inlay_hints = @import("inlay_hints.zig");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const TypedTable = @import("../types/typed_ast.zig").TypedTable;
const TypedColumn = @import("../types/typed_ast.zig").TypedColumn;
const SqlType = @import("../types/sql_type.zig").SqlType;
const Dialect = @import("../dialect/enum.zig").Dialect;

test "getInlayHints - basic types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = "test",
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                    .{
                        .name = "name",
                        .sql_type = .{ .varchar = 255 },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 3,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    const hints = try inlay_hints.getInlayHints(alloc, ast, .mysql);
    try testing.expectEqual(@as(usize, 2), hints.len);

    // Check first hint (id -> int)
    try testing.expectEqual(@as(u32, 1), hints[0].position.line); // line_no 2 - 1 = 1
    try testing.expectEqualStrings(" -> int", hints[0].label);

    // Check second hint (name -> varchar(255))
    try testing.expectEqual(@as(u32, 2), hints[1].position.line); // line_no 3 - 1 = 2
    try testing.expectEqualStrings(" -> varchar(255)", hints[1].label);
}

test "getInlayHints - custom types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = "test",
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "orders",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "status",
                        .sql_type = .{ .enum_values = &.{ "pending", "active", "completed" } },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{ "pending", "active", "completed" },
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    const hints = try inlay_hints.getInlayHints(alloc, ast, .mysql);
    try testing.expectEqual(@as(usize, 1), hints.len);
    try testing.expectEqualStrings(" -> ENUM('pending', 'active', 'completed')", hints[0].label);
}

test "getInlayHints - skip raw_sql type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = "test",
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "special",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "computed",
                        .sql_type = .{ .raw_sql = "GENERATED ALWAYS AS (id * 2)" },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    const hints = try inlay_hints.getInlayHints(alloc, ast, .mysql);
    try testing.expectEqual(@as(usize, 0), hints.len);
}

test "getInlayHints - empty schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = "test",
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };

    const hints = try inlay_hints.getInlayHints(alloc, ast, .mysql);
    try testing.expectEqual(@as(usize, 0), hints.len);
}

test "InlayHint JSON serialization" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    const protocol = @import("protocol.zig");
    try protocol.writeInlayHint(&aw.writer, .{
        .position = .{ .line = 1, .character = 10 },
        .label = " -> int",
        .kind = .type_hint,
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"line\":1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"character\":10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"label\":\" -> int\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"kind\":1") != null);
}
