const std = @import("std");
const typed_ast = @import("typed_ast.zig");
const sql_type_mod = @import("sql_type.zig");
const ast = @import("ast.zig");
const ir_version = @import("ir_version.zig");

const testing = std.testing;
const ColumnFlags = typed_ast.ColumnFlags;
const TypedColumn = typed_ast.TypedColumn;
const TypedTable = typed_ast.TypedTable;
const TypedAst = typed_ast.TypedAst;
const TypedView = typed_ast.TypedView;
const SqlType = sql_type_mod.SqlType;

// ─── ColumnFlags packed struct ────────────────────────────────

test "ColumnFlags: default is all-false" {
    const flags: ColumnFlags = .{};
    try testing.expect(!flags.nullable);
    try testing.expect(!flags.primary_key);
    try testing.expect(!flags.auto_increment);
    try testing.expect(!flags.unsigned);
    try testing.expect(!flags.inline_unique);
    try testing.expect(!flags.inline_index);
    try testing.expect(!flags.is_enum);
    try testing.expect(!flags.is_datetime);
    try testing.expect(!flags.has_timestamp_default);
    try testing.expect(!flags.on_update_current_timestamp);
    try testing.expect(!flags.is_virtual);
    try testing.expect(!flags.is_stored);
}

test "ColumnFlags: primary key" {
    const flags: ColumnFlags = .{ .primary_key = true };
    try testing.expect(flags.primary_key);
    try testing.expect(!flags.nullable);
}

test "ColumnFlags: nullable + primary key" {
    const flags: ColumnFlags = .{ .nullable = true, .primary_key = true };
    try testing.expect(flags.nullable);
    try testing.expect(flags.primary_key);
}

test "ColumnFlags: auto_increment combo" {
    const flags: ColumnFlags = .{ .primary_key = true, .auto_increment = true };
    try testing.expect(flags.primary_key);
    try testing.expect(flags.auto_increment);
    try testing.expect(!flags.unsigned);
}

test "ColumnFlags: virtual + stored" {
    const flags: ColumnFlags = .{ .is_virtual = true, .is_stored = true };
    try testing.expect(flags.is_virtual);
    try testing.expect(flags.is_stored);
}

// ─── TypedColumn ──────────────────────────────────────────────

test "TypedColumn: basic int column" {
    const col = TypedColumn{
        .name = "id",
        .sql_type = .int,
        .flags = .{ .primary_key = true, .auto_increment = true },
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 1,
    };
    try testing.expectEqualStrings("id", col.name);
    try testing.expect(col.flags.primary_key);
    try testing.expect(col.flags.auto_increment);
    try testing.expect(!col.flags.nullable);
    try testing.expectEqual(@as(?[]const u8, null), col.default);
    try testing.expectEqual(@as(?[]const u8, null), col.doc);
    try testing.expectEqual(@as(?[]const u8, null), col.ss_symbol);
}

test "TypedColumn: varchar with default and comment" {
    const col = TypedColumn{
        .name = "email",
        .sql_type = .{ .varchar = 255 },
        .flags = .{},
        .default = "'user@example.com'",
        .check = null,
        .comment = "User email address",
        .enum_values = &.{},
        .line_no = 5,
    };
    try testing.expectEqualStrings("email", col.name);
    try testing.expectEqualStrings("'user@example.com'", col.default.?);
    try testing.expectEqualStrings("User email address", col.comment.?);
    try testing.expect(!col.flags.primary_key);
}

test "TypedColumn: enum type" {
    const vals = [_][]const u8{ "draft", "published", "archived" };
    const col = TypedColumn{
        .name = "status",
        .sql_type = .{ .enum_values = &vals },
        .flags = .{ .is_enum = true },
        .default = "'draft'",
        .check = null,
        .comment = null,
        .enum_values = &vals,
        .line_no = 3,
    };
    try testing.expect(col.flags.is_enum);
    try testing.expectEqual(@as(usize, 3), col.enum_values.len);
}

test "TypedColumn: with doc directive" {
    const col = TypedColumn{
        .name = "name",
        .sql_type = .{ .varchar = 100 },
        .doc = "Full name of the user",
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 2,
    };
    try testing.expectEqualStrings("Full name of the user", col.doc.?);
}

test "TypedColumn: ss_symbol for SQLite roundtrip" {
    const col = TypedColumn{
        .name = "amount",
        .sql_type = .{ .decimal = .{ .precision = 10, .scale = 2 } },
        .ss_symbol = "M",
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 4,
    };
    try testing.expectEqualStrings("M", col.ss_symbol.?);
}

test "TypedColumn: generated expression" {
    const col = TypedColumn{
        .name = "full_name",
        .sql_type = .{ .varchar = 255 },
        .generated_expr = "CONCAT(first_name, ' ', last_name)",
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 7,
    };
    try testing.expectEqualStrings("CONCAT(first_name, ' ', last_name)", col.generated_expr.?);
}

// ─── TypedTable ───────────────────────────────────────────────

test "TypedTable: basic initialization" {
    const table = TypedTable{
        .name = "users",
        .comment = null,
        .engine = "InnoDB",
        .columns = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 10,
    };
    try testing.expectEqualStrings("users", table.name);
    try testing.expectEqualStrings("InnoDB", table.engine.?);
    try testing.expectEqual(@as(usize, 0), table.columns.len);
    try testing.expectEqual(@as(?[]const u8, null), table.comment);
    try testing.expectEqual(@as(?[]const u8, null), table.doc);
}

test "TypedTable: with doc and comment" {
    const table = TypedTable{
        .name = "orders",
        .comment = "Order records",
        .doc = "Customer orders table",
        .engine = null,
        .columns = &.{},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 15,
    };
    try testing.expectEqualStrings("Order records", table.comment.?);
    try testing.expectEqualStrings("Customer orders table", table.doc.?);
}

// ─── TypedView ────────────────────────────────────────────────

test "TypedView: basic initialization" {
    const view = TypedView{
        .name = "active_users",
        .query = "SELECT * FROM users WHERE active = 1",
        .comment = null,
        .line_no = 20,
    };
    try testing.expectEqualStrings("active_users", view.name);
    try testing.expectEqualStrings("SELECT * FROM users WHERE active = 1", view.query);
    try testing.expect(view.union_op == null);
    try testing.expectEqual(@as(?[]const u8, null), view.second_query);
}

test "TypedView: with doc directive" {
    const view = TypedView{
        .name = "user_stats",
        .query = "SELECT user_id, COUNT(*) FROM orders GROUP BY user_id",
        .comment = "Order counts per user",
        .doc = "Aggregated order statistics",
        .line_no = 25,
    };
    try testing.expectEqualStrings("Aggregated order statistics", view.doc.?);
}

// ─── TypedAst ─────────────────────────────────────────────────

test "TypedAst: initialization with empty tables" {
    const schema = TypedAst{
        .schema_name = "myapp",
        .schema_charset = "utf8mb4",
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqualStrings("myapp", schema.schema_name.?);
    try testing.expectEqualStrings("utf8mb4", schema.schema_charset.?);
    try testing.expectEqual(@as(usize, 0), schema.tables.len);
    try testing.expectEqual(@as(usize, 0), schema.views.len);
    try testing.expectEqual(ir_version.CURRENT_IR_VERSION, schema.ir_version);
}

test "TypedAst: defaults for optional fields" {
    const schema = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    try testing.expectEqual(@as(?[]const u8, null), schema.schema_name);
    try testing.expectEqual(@as(?[]const u8, null), schema.schema_charset);
    try testing.expectEqual(@as(usize, 0), schema.custom_types.len);
}
