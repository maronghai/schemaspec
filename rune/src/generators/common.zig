const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const Writer = std.Io.Writer;

// ─── Shared Generator Helpers ────────────────────────────────
// Common utilities used by multiple generators (prisma, drizzle,
// json_schema, docs, knex, typeorm, sqlalchemy). Eliminates
// duplicated patterns for enum detection, FK lookup, default
// formatting, and enum value rendering.

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

// ─── Default Value Formatting ────────────────────────────────
// Shared by ORM generators (drizzle, knex, typeorm, sqlalchemy).
// Each generator provides language-specific formatting callbacks
// via a DefaultFormatter config struct.

/// Language-specific formatting callbacks for default values.
pub const DefaultFormatter = struct {
    /// Output for SQL `true` / `TRUE` (e.g. "true", "'true'")
    boolTrue: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `false` / `FALSE` (e.g. "false", "'false'")
    boolFalse: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `null` / `NULL` (e.g. "null", "None")
    nullValue: *const fn (w: *Writer) anyerror!void,
    /// Output for `NOW()` / `now()` / `CURRENT_TIMESTAMP`
    now: *const fn (w: *Writer) anyerror!void,
    /// Format a string default (e.g. "'foo'", `"foo"`)
    formatString: *const fn (w: *Writer, dflt: []const u8) anyerror!void,
};

/// Shared default value writer. Parses the raw SQL default value and
/// delegates formatting to language-specific callbacks.
pub fn writeFormattedDefault(w: *Writer, dflt: []const u8, fmt: DefaultFormatter) !void {
    if (std.mem.eql(u8, dflt, "true") or std.mem.eql(u8, dflt, "TRUE")) {
        try fmt.boolTrue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "false") or std.mem.eql(u8, dflt, "FALSE")) {
        try fmt.boolFalse(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "null") or std.mem.eql(u8, dflt, "NULL")) {
        try fmt.nullValue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "NOW()") or std.mem.eql(u8, dflt, "now()") or
        std.mem.eql(u8, dflt, "CURRENT_TIMESTAMP"))
    {
        try fmt.now(w);
        return;
    }
    if (std.fmt.parseInt(i64, dflt, 10)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, dflt)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}
    try fmt.formatString(w, dflt);
}
