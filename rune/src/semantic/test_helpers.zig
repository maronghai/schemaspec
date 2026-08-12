const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const pass_manager = @import("pass_manager.zig");
const diag_mod = @import("../diagnostic.zig");

const ResolvedTable = resolved_ast.ResolvedTable;
const PassContext = pass_manager.PassContext;

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

// ─── PassContext Test Helpers ─────────────────────────────────

const symbol_table_mod = @import("../types/symbol_table.zig");

pub const PassContextOptions = struct {
    schema: ?ast_mod.Schema = null,
    templates: ?std.StringHashMap(*const ast_mod.Template) = null,
    template_refs: ?std.StringHashMap(void) = null,
    init_symbol_table: bool = false,
};

/// Shared test helper: create a PassContext for semantic pass tests.
pub fn makePassCtx(
    alloc: std.mem.Allocator,
    tables: *std.ArrayList(ResolvedTable),
    diagnostics: *diag_mod.DiagnosticCollector,
    opts: PassContextOptions,
) PassContext {
    const st: symbol_table_mod.SymbolTable = if (opts.init_symbol_table) blk: {
        var sym = symbol_table_mod.SymbolTable.init(alloc);
        for (tables.items) |*t| {
            _ = sym.registerTable(t.name, t) catch {};
        }
        break :blk sym;
    } else symbol_table_mod.SymbolTable.init(alloc);
    return PassContext.init(
        alloc,
        tables,
        opts.schema,
        opts.templates orelse std.StringHashMap(*const ast_mod.Template).init(alloc),
        if (opts.template_refs) |tr| tr else std.StringHashMap(void).init(alloc),
        diagnostics,
        st,
    );
}
