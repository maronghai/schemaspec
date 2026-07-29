const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const Writer = std.Io.Writer;

// ─── Shared Generator Helpers ────────────────────────────────
// Common utilities used by multiple generators (prisma, drizzle,
// json_schema, docs). Eliminates duplicated patterns for enum
// detection, FK lookup, and enum value rendering.

/// Returns true if any table in the schema has at least one enum column.
pub fn hasEnumColumns(tables: []const typed_ast.TypedTable) bool {
    for (tables) |table| {
        for (table.columns) |col| {
            if (col.flags.is_enum) return true;
        }
    }
    return false;
}

/// Find a single-column FK in `table.fks` that references `col_name`.
/// Returns the FK declaration if found, null otherwise.
pub fn findFkForColumn(table: typed_ast.TypedTable, col_name: []const u8) ?typed_ast.FkDecl {
    for (table.fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col_name)) {
            return fk;
        }
    }
    return null;
}

/// Write enum values joined by `sep`, each wrapped in `quote` characters.
/// Example: writeEnumValuesJoin(w, vals, ", ", "'") → 'a', 'b', 'c'
pub fn writeEnumValuesJoin(w: *Writer, values: []const []const u8, sep: []const u8, quote: []const u8) !void {
    for (values, 0..) |val, i| {
        if (i > 0) try w.writeAll(sep);
        try w.writeAll(quote);
        try w.writeAll(val);
        try w.writeAll(quote);
    }
}

/// Count tables that have at least one non-primary-key index.
pub fn tableHasNonPkIndexes(table: typed_ast.TypedTable) bool {
    for (table.indexes) |idx| {
        if (idx.kind != .primary_key) return true;
    }
    return false;
}

/// Count tables that have at least one composite (multi-column) FK.
pub fn tableHasCompositeFks(table: typed_ast.TypedTable) bool {
    for (table.fks) |fk| {
        if (fk.fields.len > 1) return true;
    }
    return false;
}
