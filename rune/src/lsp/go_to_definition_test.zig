const std = @import("std");
const go_to_definition = @import("go_to_definition.zig");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const Position = @import("protocol.zig").Position;

// ─── Go-to-Definition Tests ──────────────────────────────────
// Tests for lsp/go_to_definition.zig: FK reference and column FK navigation.

test "getDefinition: FK reference navigates to target table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "posts",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 8,
                    },
                },
                .indexes = &.{},
                .line_no = 5,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    // Position on FK line (7 = 0-based line 7 = 1-based line 8)
    const result = go_to_definition.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 7, .character = 0 });
    try std.testing.expect(result != null);
    const loc = result.?;
    try std.testing.expectEqualStrings("file:///test.ss", loc.uri);
    // users table is at line_no=1, so 0-based line 0
    try std.testing.expectEqual(@as(u32, 0), loc.range.start.line);
}

test "getDefinition: FK column navigates to target table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "posts",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "user_id",
                        .sql_type = .{ .varchar = 36 },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 7,
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 10,
                    },
                },
                .indexes = &.{},
                .line_no = 5,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    // Position on column line (6 = 0-based line 6 = 1-based line 7)
    const result = go_to_definition.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 6, .character = 0 });
    try std.testing.expect(result != null);
    const loc = result.?;
    // users table is at line_no=1, so 0-based line 0
    try std.testing.expectEqual(@as(u32, 0), loc.range.start.line);
}

test "getDefinition: non-FK column returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
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

    // Position on non-FK column line (2 = 0-based line 2 = 1-based line 3)
    const result = go_to_definition.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 2, .character = 0 });
    try std.testing.expectEqual(@as(?@import("protocol.zig").Location, null), result);
}

test "getDefinition: table name line returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    // Position on table definition line (0 = 0-based line 0 = 1-based line 1)
    const result = go_to_definition.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 0, .character = 0 });
    try std.testing.expectEqual(@as(?@import("protocol.zig").Location, null), result);
}

test "getDefinition: FK in same table navigates to target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "orders",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "user_id",
                        .sql_type = .{ .varchar = 36 },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 7,
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 10,
                    },
                },
                .indexes = &.{},
                .line_no = 5,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };

    // Position on user_id column (0-based line 6 = 1-based line 7)
    const result = go_to_definition.getDefinition(alloc, ast, "file:///test.ss", .{ .line = 6, .character = 0 });
    try std.testing.expect(result != null);
    const loc = result.?;
    // users table is at line_no=1, so 0-based line 0
    try std.testing.expectEqual(@as(u32, 0), loc.range.start.line);
}
