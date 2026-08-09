const std = @import("std");
const ast = @import("ast.zig");
const resolved_ast = @import("resolved_ast.zig");
const ir_version = @import("ir_version.zig");

const testing = std.testing;
const ResolvedTable = resolved_ast.ResolvedTable;
const ResolvedAst = resolved_ast.ResolvedAst;
const Field = ast.Field;
const TypeInfo = ast.TypeInfo;
const FkDecl = ast.FkDecl;
const IndexDecl = ast.IndexDecl;
const IndexType = ast.IndexType;
const CustomType = ast.CustomType;
const View = ast.View;
const SqlComment = ast.SqlComment;

// ─── ResolvedTable ────────────────────────────────────────────

test "ResolvedTable: basic initialization" {
    const table = ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = "InnoDB",
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 10,
    };
    try testing.expectEqualStrings("users", table.name);
    try testing.expectEqualStrings("InnoDB", table.engine.?);
    try testing.expectEqual(@as(?[]const u8, null), table.comment);
    try testing.expectEqual(@as(?[]const u8, null), table.doc);
    try testing.expectEqual(@as(usize, 0), table.fields.len);
    try testing.expectEqual(@as(usize, 0), table.fks.len);
    try testing.expectEqual(@as(usize, 0), table.indexes.len);
}

test "ResolvedTable: with comment and doc" {
    const table = ResolvedTable{
        .name = "orders",
        .comment = "Customer orders",
        .doc = "Main orders table",
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 20,
    };
    try testing.expectEqualStrings("Customer orders", table.comment.?);
    try testing.expectEqualStrings("Main orders table", table.doc.?);
}

test "ResolvedTable: with fields" {
    var fields = [_]Field{
        .{
            .name = "id",
            .type_info = .{ .simple = "n" },
            .modifiers = &.{},
            .default_val = null,
            .check = null,
            .fk = null,
            .comment = null,
            .line_no = 1,
        },
        .{
            .name = "email",
            .type_info = .{ .simple = "s" },
            .modifiers = &.{},
            .default_val = null,
            .check = null,
            .fk = null,
            .comment = "Unique email",
            .line_no = 2,
        },
    };
    const table = ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = &fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    try testing.expectEqual(@as(usize, 2), table.fields.len);
    try testing.expectEqualStrings("id", table.fields[0].name);
    try testing.expectEqualStrings("email", table.fields[1].name);
}

test "ResolvedTable: with foreign keys" {
    const fks = [_]FkDecl{
        .{
            .fields = &.{"user_id"},
            .ref_table = "users",
            .ref_fields = &.{"id"},
            .actions = &.{},
            .line_no = 5,
        },
    };
    const table = ResolvedTable{
        .name = "orders",
        .comment = null,
        .engine = null,
        .fields = &.{},
        .fks = &fks,
        .indexes = &.{},
        .line_no = 1,
    };
    try testing.expectEqual(@as(usize, 1), table.fks.len);
    try testing.expectEqualStrings("users", table.fks[0].ref_table);
}

test "ResolvedTable: with indexes" {
    const indexes = [_]IndexDecl{
        .{
            .kind = .unique,
            .name = "idx_email",
            .fields = &.{"email"},
            .descending = &.{false},
            .line_no = 3,
        },
    };
    const table = ResolvedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &indexes,
        .line_no = 1,
    };
    try testing.expectEqual(@as(usize, 1), table.indexes.len);
    try testing.expectEqual(IndexType.unique, table.indexes[0].kind);
}

// ─── ResolvedAst ──────────────────────────────────────────────

test "ResolvedAst: initialization with empty tables" {
    const schema = ResolvedAst{
        .schema_name = "myapp",
        .schema_charset = "utf8mb4",
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqualStrings("myapp", schema.schema_name.?);
    try testing.expectEqualStrings("utf8mb4", schema.schema_charset.?);
    try testing.expectEqual(@as(usize, 0), schema.tables.len);
    try testing.expectEqual(@as(usize, 0), schema.views.len);
    try testing.expectEqual(@as(usize, 0), schema.custom_types.len);
    try testing.expectEqual(ir_version.CURRENT_IR_VERSION, schema.ir_version);
}

test "ResolvedAst: defaults for optional fields" {
    const schema = ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqual(@as(?[]const u8, null), schema.schema_name);
    try testing.expectEqual(@as(?[]const u8, null), schema.schema_charset);
}

test "ResolvedAst: with custom types" {
    const custom = [_]CustomType{
        .{
            .name = "email_addr",
            .base = .{ .varchar_explicit = 255 },
            .dialect_overrides = &.{},
            .line_no = 1,
        },
    };
    const schema = ResolvedAst{
        .schema_name = "test",
        .schema_charset = null,
        .custom_types = &custom,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqual(@as(usize, 1), schema.custom_types.len);
    try testing.expectEqualStrings("email_addr", schema.custom_types[0].name);
}

test "ResolvedAst: with views" {
    const views = [_]View{
        .{
            .name = "active_users",
            .query = "SELECT * FROM users WHERE active = 1",
            .comment = null,
            .line_no = 15,
        },
    };
    const schema = ResolvedAst{
        .schema_name = "myapp",
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &views,
        .sql_comments = &.{},
    };
    try testing.expectEqual(@as(usize, 1), schema.views.len);
    try testing.expectEqualStrings("active_users", schema.views[0].name);
}

test "ResolvedAst: with sql comments" {
    const comments = [_]SqlComment{
        .{ .text = "-- This is a test", .line_no = 1 },
        .{ .text = "-- Another comment", .line_no = 5 },
    };
    const schema = ResolvedAst{
        .schema_name = "test",
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &comments,
    };
    try testing.expectEqual(@as(usize, 2), schema.sql_comments.len);
    try testing.expectEqualStrings("-- This is a test", schema.sql_comments[0].text);
    try testing.expectEqualStrings("-- Another comment", schema.sql_comments[1].text);
}

test "ResolvedAst: with multiple tables" {
    const tables = [_]ResolvedTable{
        .{
            .name = "users",
            .comment = null,
            .engine = null,
            .fields = &.{},
            .fks = &.{},
            .indexes = &.{},
            .line_no = 1,
        },
        .{
            .name = "posts",
            .comment = null,
            .engine = null,
            .fields = &.{},
            .fks = &.{},
            .indexes = &.{},
            .line_no = 10,
        },
    };
    const schema = ResolvedAst{
        .schema_name = "blog",
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &tables,
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqual(@as(usize, 2), schema.tables.len);
    try testing.expectEqualStrings("users", schema.tables[0].name);
    try testing.expectEqualStrings("posts", schema.tables[1].name);
}
