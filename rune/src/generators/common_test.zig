const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const common = @import("common.zig");

const testing = std.testing;

// ─── Shared Generator Test Helpers ────────────────────────────
// Common test utilities used by all generator *_test.zig files.
// Eliminates ~80 lines of duplicated helper definitions.

pub const SqlType = sql_type_mod.SqlType;
pub const ColumnFlags = typed_ast.ColumnFlags;
pub const FkDecl = ast_mod.FkDecl;
pub const IndexDecl = ast_mod.IndexDecl;

pub fn makeTestColumn(name: []const u8, sql_type_val: SqlType) typed_ast.TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type_val,
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = if (sql_type_val == .enum_values) sql_type_val.enum_values else &.{},
        .line_no = 1,
    };
}

pub fn makeTestColumnWithFlags(name: []const u8, sql_type_val: SqlType, flags: ColumnFlags) typed_ast.TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type_val,
        .flags = flags,
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = if (sql_type_val == .enum_values) sql_type_val.enum_values else &.{},
        .line_no = 1,
    };
}

pub fn makeTestTable(name: []const u8, columns: []const typed_ast.TypedColumn) typed_ast.TypedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .columns = columns,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

pub fn makeTestTableWithFks(name: []const u8, columns: []const typed_ast.TypedColumn, fks: []const FkDecl) typed_ast.TypedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .columns = columns,
        .fks = fks,
        .indexes = &.{},
        .line_no = 1,
    };
}

pub fn makeTestTableWithIndexes(name: []const u8, columns: []const typed_ast.TypedColumn, indexes: []const IndexDecl) typed_ast.TypedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .columns = columns,
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    };
}

pub fn makeTestAst(tables: []const typed_ast.TypedTable) typed_ast.TypedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

pub fn makeTestAstWithName(schema_name: ?[]const u8, tables: []const typed_ast.TypedTable) typed_ast.TypedAst {
    return .{
        .schema_name = schema_name,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

// ─── Unit Tests ──────────────────────────────────────────────

test "findFkRefTable: single-field FK matches" {
    const fks = [_]FkDecl{.{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 0,
    }};
    try testing.expectEqualStrings("users", common.findFkRefTable("user_id", &fks) orelse return error.TestFailed);
}

test "findFkRefTable: multi-field FK does not match" {
    const fks = [_]FkDecl{.{
        .fields = &.{ "org_id", "user_id" },
        .ref_table = "users",
        .ref_fields = &.{ "org_id", "id" },
        .actions = &.{},
        .line_no = 0,
    }};
    try testing.expect(common.findFkRefTable("user_id", &fks) == null);
}

test "findFkRefTable: no FK returns null" {
    try testing.expect(common.findFkRefTable("email", &.{}) == null);
}

test "toCamelSingular: strips trailing s" {
    try testing.expectEqualStrings("user", common.toCamelSingular("users"));
    try testing.expectEqualStrings("categorie", common.toCamelSingular("categories"));
}

test "toCamelSingular: single char stays" {
    try testing.expectEqualStrings("s", common.toCamelSingular("s"));
}

test "toCamelSingular: no trailing s stays" {
    try testing.expectEqualStrings("user", common.toCamelSingular("user"));
}

test "toCamelSingular: empty string" {
    try testing.expectEqualStrings("", common.toCamelSingular(""));
}

test "tableHasNonPkIndexes: returns true for non-PK index" {
    const table = makeTestTableWithIndexes("users", &.{}, &.{
        .{ .kind = .unique, .name = "uk_email", .fields = &.{"email"}, .descending = &.{}, .line_no = 0 },
    });
    try testing.expect(common.tableHasNonPkIndexes(table));
}

test "tableHasNonPkIndexes: returns false for only PK index" {
    const table = makeTestTableWithIndexes("users", &.{}, &.{
        .{ .kind = .primary_key, .name = "pk_id", .fields = &.{"id"}, .descending = &.{}, .line_no = 0 },
    });
    try testing.expect(!common.tableHasNonPkIndexes(table));
}

test "tableHasNonPkIndexes: returns false for no indexes" {
    const table = makeTestTable("users", &.{});
    try testing.expect(!common.tableHasNonPkIndexes(table));
}

test "tableHasCompositeFks: returns true for multi-column FK" {
    const table = makeTestTableWithFks("orders", &.{}, &.{
        .{ .fields = &.{ "org_id", "user_id" }, .ref_table = "users", .ref_fields = &.{ "org_id", "id" }, .actions = &.{}, .line_no = 0 },
    });
    try testing.expect(common.tableHasCompositeFks(table));
}

test "tableHasCompositeFks: returns false for single-column FK" {
    const table = makeTestTableWithFks("orders", &.{}, &.{
        .{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 0 },
    });
    try testing.expect(!common.tableHasCompositeFks(table));
}

test "writeJsonValue: integer" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try common.writeJsonValue(&aw.writer, "42");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("42", result);
}

test "writeJsonValue: float" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try common.writeJsonValue(&aw.writer, "3.14");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}

test "writeJsonValue: null" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try common.writeJsonValue(&aw.writer, "NULL");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("null", result);
}

test "writeJsonValue: boolean true" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try common.writeJsonValue(&aw.writer, "true");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("true", result);
}

test "writeJsonValue: string" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try common.writeJsonValue(&aw.writer, "hello");
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\"hello\"", result);
}

test "hasAnyEnums: returns true when enum column exists" {
    const col = makeTestColumnWithFlags("role", .{ .enum_values = &.{ "admin", "user" } }, .{ .is_enum = true });
    const table = makeTestTable("users", &.{col});
    const ast = makeTestAst(&.{table});
    try testing.expect(common.hasAnyEnums(ast));
}

test "hasAnyEnums: returns false when no enum columns" {
    const col = makeTestColumn("name", .text);
    const table = makeTestTable("users", &.{col});
    const ast = makeTestAst(&.{table});
    try testing.expect(!common.hasAnyEnums(ast));
}

test "hasAnyEnums: returns false for empty schema" {
    const ast = makeTestAst(&.{});
    try testing.expect(!common.hasAnyEnums(ast));
}

test "hasAnyCompositeFks: returns true when composite FK exists" {
    const fk = FkDecl{
        .fields = &.{ "org_id", "user_id" },
        .ref_table = "users",
        .ref_fields = &.{ "org_id", "id" },
        .actions = &.{},
        .line_no = 0,
    };
    const table = makeTestTableWithFks("orders", &.{}, &.{fk});
    const ast = makeTestAst(&.{table});
    try testing.expect(common.hasAnyCompositeFks(ast));
}

test "hasAnyCompositeFks: returns false for single-column FKs only" {
    const fk = FkDecl{
        .fields = &.{"user_id"},
        .ref_table = "users",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 0,
    };
    const table = makeTestTableWithFks("orders", &.{}, &.{fk});
    const ast = makeTestAst(&.{table});
    try testing.expect(!common.hasAnyCompositeFks(ast));
}

test "hasAnyCompositeFks: returns false for empty schema" {
    const ast = makeTestAst(&.{});
    try testing.expect(!common.hasAnyCompositeFks(ast));
}
