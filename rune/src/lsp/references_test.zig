const std = @import("std");
const references_mod = @import("references.zig");
const typed_ast = @import("../types/typed_ast.zig");

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

// ─── getReferences Tests ─────────────────────────────────────

test "getReferences: table definition returns definition reference" {
    // Document: "# users {\n  id n ++ PK\n}\n"
    // Line 0: "# users {" — cursor at char 2 (start of "users") matches
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
    const refs = references_mod.getReferences(testing.allocator, ast, 0, 2, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    try testing.expect(refs.len >= 1);
    try testing.expect(refs[0].is_definition);
}

test "getReferences: FK reference returns non-definition reference" {
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
    const refs = references_mod.getReferences(testing.allocator, ast, 0, 2, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    // Should have definition + FK reference
    try testing.expect(refs.len >= 2);
    var has_definition = false;
    var has_reference = false;
    for (refs) |ref| {
        if (ref.is_definition) has_definition = true;
        if (!ref.is_definition) has_reference = true;
    }
    try testing.expect(has_definition);
    try testing.expect(has_reference);
}

test "getReferences: no references returns empty" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = emptyTypedAst();
    const refs = references_mod.getReferences(testing.allocator, ast, 0, 0, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    try testing.expectEqual(@as(usize, 0), refs.len);
}

test "getReferences: cursor on column with no FK references" {
    const doc = "# users {\n  id n ++ PK\n  email s\n}\n";
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
                    .{
                        .name = "email",
                        .sql_type = .{ .varchar = 255 },
                        .line_no = 3,
                        .flags = .{},
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
    const refs = references_mod.getReferences(testing.allocator, ast, 2, 2, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    // Column with no FK references should return empty
    try testing.expectEqual(@as(usize, 0), refs.len);
}

// ─── Additional Reference Tests ─────────────────────────────

test "getReferences: multiple FK references to same table" {
    const doc = "# users {\n  id n ++ PK\n}\n# orders {\n  user_id n -> users.id\n}\n# payments {\n  user_id n -> users.id\n}\n";
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
            .{
                .name = "payments",
                .line_no = 7,
                .columns = &.{
                    .{
                        .name = "user_id",
                        .sql_type = .int,
                        .line_no = 8,
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
                        .line_no = 8,
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
    // Cursor on "users" table name
    const refs = references_mod.getReferences(testing.allocator, ast, 0, 2, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    // Should have definition + 2 FK references
    try testing.expect(refs.len >= 3);
    var definition_count: u32 = 0;
    for (refs) |ref| {
        if (ref.is_definition) definition_count += 1;
    }
    try testing.expectEqual(@as(u32, 1), definition_count);
}

test "getReferences: cursor on FK field returns reference" {
    // Test that when cursor is on a column that is referenced by FKs,
    // the function finds those FK references
    const doc = "# users {\n  id n ++ PK\n}\n# orders {\n  user_id n -> users.id\n}\n# payments {\n  amount n\n  order_id n -> orders.id\n}\n";
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
                        .name = "id",
                        .sql_type = .int,
                        .line_no = 4,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
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
            .{
                .name = "payments",
                .line_no = 7,
                .columns = &.{
                    .{
                        .name = "amount",
                        .sql_type = .int,
                        .line_no = 8,
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                    .{
                        .name = "order_id",
                        .sql_type = .int,
                        .line_no = 9,
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"order_id"},
                        .ref_table = "orders",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 9,
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
    // Cursor on "orders" table name (line 3, char 2)
    // Should find: definition + FK reference from payments
    const refs = references_mod.getReferences(testing.allocator, ast, 3, 2, "file:///test.ss", doc);
    defer testing.allocator.free(refs);
    // Should find at least the definition and the FK reference
    try testing.expect(refs.len >= 2);
    var has_definition = false;
    var has_reference = false;
    for (refs) |ref| {
        if (ref.is_definition) has_definition = true;
        if (!ref.is_definition) has_reference = true;
    }
    try testing.expect(has_definition);
    try testing.expect(has_reference);
}
