const std = @import("std");
const resolved_ast = @import("../types/resolved_ast.zig");
const typed_ast = @import("../types/typed_ast.zig");
const dialect_mod = @import("../dialect/dialect.zig");

// ─── Shared Diff Emit Utilities ──────────────────────────────
//
// Common helpers used by both diff/format.zig and diff/migrate.zig.
// Eliminates duplication of ALTER TABLE header logic, comma emission,
// and table/view lookup functions.

/// Emit "ALTER TABLE <name>\n" header, but only once per table.
/// `table_has_ops` tracks whether the header has been emitted.
pub fn beginAlterTable(w: anytype, backend: *const dialect_mod.DialectBackend, table_name: []const u8, table_has_ops: *bool) !void {
    if (!table_has_ops.*) {
        try w.writeAll("ALTER TABLE ");
        try backend.quoteIdent(w, table_name);
        try w.writeAll("\n");
        table_has_ops.* = true;
    }
}

/// Emit a comma separator between ALTER TABLE sub-operations.
/// `needs_comma` tracks whether a comma prefix is needed.
pub fn emitComma(w: anytype, needs_comma: *bool) !void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
}

/// Look up a table by name in a ResolvedAst.
pub fn findResolvedTable(ast: resolved_ast.ResolvedAst, name: []const u8) ?resolved_ast.ResolvedTable {
    for (ast.tables) |table| {
        if (std.mem.eql(u8, table.name, name)) return table;
    }
    return null;
}

/// Look up a view by name in a TypedAst.
pub fn findTypedView(typed: typed_ast.TypedAst, name: []const u8) ?typed_ast.TypedView {
    for (typed.views) |view| {
        if (std.mem.eql(u8, view.name, name)) return view;
    }
    return null;
}
