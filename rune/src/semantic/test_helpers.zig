const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");

/// Shared test helper: create a minimal Field with default values.
pub fn makeTestField(name: []const u8, type_info: ast_mod.TypeInfo) ast_mod.Field {
    return .{
        .name = name,
        .type_info = type_info,
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

/// Shared test helper: create a Field with explicit modifiers.
pub fn makeTestFieldWithMods(name: []const u8, type_info: ast_mod.TypeInfo, mods: []const ast_mod.Modifier) ast_mod.Field {
    return .{
        .name = name,
        .type_info = type_info,
        .modifiers = mods,
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

/// Shared test helper: create a minimal Ast with no schema or comments.
pub fn makeTestAst(_: std.mem.Allocator, tables: []const ast_mod.Table, templates: []const ast_mod.Template) ast_mod.Ast {
    return .{
        .schema = null,
        .templates = templates,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

/// Shared test helper: create a minimal TypedColumn with default values.
pub fn makeTestColumn(name: []const u8, sql_type: sql_type_mod.SqlType) typed_ast_mod.TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type,
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = if (sql_type == .enum_values) sql_type.enum_values else &.{},
        .line_no = 1,
    };
}
