const std = @import("std");
const rename_mod = @import("rename.zig");
const typed_ast = @import("../types/typed_ast.zig");
const protocol = @import("protocol.zig");

const testing = std.testing;

// ─── Helper: Create empty TypedAst ───────────────────────────

fn emptyTypedAst() typed_ast.TypedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
}

// ─── prepareRename Tests ─────────────────────────────────────

test "prepareRename: cursor on non-table line returns null" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = emptyTypedAst();
    // Line 2 (empty line) — no word to find
    const result = rename_mod.prepareRename(ast, .{ .line = 2, .character = 0 }, doc);
    try testing.expect(result == null);
}

test "prepareRename: unknown word returns null" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .line_no = 2,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    // Cursor on "PK" — not a table or column name in the AST
    const result = rename_mod.prepareRename(ast, .{ .line = 1, .character = 12 }, doc);
    try testing.expect(result == null);
}

// ─── RenameResult Tests ──────────────────────────────────────

test "RenameResult: struct fields" {
    // Verify the struct has the expected fields
    const result = rename_mod.RenameResult{
        .changes = &.{},
    };
    try testing.expectEqual(@as(usize, 0), result.changes.len);
}

// ─── prepareRename: Positive Cases ───────────────────────────

test "prepareRename: cursor on table name returns word" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    // Cursor at "users" (line 0, char 2)
    const result = rename_mod.prepareRename(ast, .{ .line = 0, .character = 2 }, doc);
    try testing.expect(result != null);
    try testing.expectEqualStrings("users", result.?);
}

test "prepareRename: cursor on column name returns word" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .line_no = 2,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    // Cursor at "id" (line 1, char 2)
    const result = rename_mod.prepareRename(ast, .{ .line = 1, .character = 2 }, doc);
    try testing.expect(result != null);
    try testing.expectEqualStrings("id", result.?);
}

// ─── getRenameLinks Tests ────────────────────────────────────

test "getRenameLinks: table rename updates FK references" {
    const doc = "# users {\n  id n ++ PK\n}\n# orders {\n  user_id n -> users.id\n}\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .line_no = 2,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
            .{
                .name = "orders",
                .line_no = 4,
                .columns = &.{
                    .{
                        .name = "user_id",
                        .sql_type = .int,
                        .line_no = 5,
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 5,
                    },
                },
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    // Rename "users" to "accounts" at line 0, char 2
    const result = rename_mod.getRenameLinks(testing.allocator, ast, .{ .line = 0, .character = 2 }, doc, "accounts");
    try testing.expect(result != null);
    // Should have edits for both the table definition and the FK reference
    try testing.expect(result.?.changes.len >= 2);
    // Free the allocated changes
    testing.allocator.free(result.?.changes);
}

// ─── v0.334.0: real Rune FK syntax + no-duplicate-edits ──────

test "getRenameLinks: exactly one edit per occurrence with > FK syntax" {
    // Real Rune syntax: `user_id > users.id`. Renaming users must produce
    // exactly 2 edits (declaration + FK line), each at a distinct position —
    // the old byte-by-byte scan emitted 3 overlapping edits at one position.
    const doc = "# users {\n  id n ++\n}\n# orders {\n  user_id n > users.id\n}\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
            .{
                .name = "orders",
                .line_no = 4,
                .columns = &.{},
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 5,
                    },
                },
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = rename_mod.getRenameLinks(testing.allocator, ast, .{ .line = 0, .character = 2 }, doc, "accounts");
    try testing.expect(result != null);
    defer testing.allocator.free(result.?.changes);
    try testing.expectEqual(@as(usize, 2), result.?.changes.len);
    // Edits must not overlap: declaration at line 0, FK reference at line 4.
    try testing.expectEqual(@as(u32, 0), result.?.changes[0].range.start.line);
    try testing.expectEqual(@as(u32, 4), result.?.changes[1].range.start.line);
}

test "getRenameLinks: comments are never renamed" {
    // A comment mentioning a table name must not produce an edit — only
    // AST-known positions (declarations, FK lines) get edited.
    const doc = "# users\nid n ++\n: TODO fix users handling later\n";
    const ast = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .line_no = 1,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .comment = null,
                .engine = null,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = rename_mod.getRenameLinks(testing.allocator, ast, .{ .line = 0, .character = 2 }, doc, "accounts");
    try testing.expect(result != null);
    defer testing.allocator.free(result.?.changes);
    // Exactly one edit: the table declaration. The comment line is untouched.
    try testing.expectEqual(@as(usize, 1), result.?.changes.len);
    try testing.expectEqual(@as(u32, 0), result.?.changes[0].range.start.line);
}
