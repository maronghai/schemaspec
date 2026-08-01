const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");

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
