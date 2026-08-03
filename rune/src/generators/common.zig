const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;

// Re-export sub-modules for backward compatibility.
pub const common_defaults = @import("common_defaults.zig");
pub const common_check = @import("common_check.zig");

// ─── Shared Generator Helpers ────────────────────────────────
// Common utilities used by multiple generators. Eliminates
// duplicated patterns for table analysis and default formatting.

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

// ─── Re-exported Defaults API ─────────────────────────────────
// ORM generators import these via `common.writeFormattedDefault`.

pub const DefaultFormatter = common_defaults.DefaultFormatter;
pub const OrmTarget = common_defaults.OrmTarget;
pub const getOrmFormatter = common_defaults.getOrmFormatter;
pub const writeFormattedDefault = common_defaults.writeFormattedDefault;

// ─── Re-exported CHECK Constraint Parsers ─────────────────────
// API generators (json_schema, openapi) import these via `common.parseRange`.

pub const Range = common_check.Range;
pub const Comparison = common_check.Comparison;
pub const parseRange = common_check.parseRange;
pub const parseComparison = common_check.parseComparison;
pub const parseInList = common_check.parseInList;

// ─── JSON Value Writer ────────────────────────────────────────

pub fn writeJsonValue(w: *std.Io.Writer, val: []const u8) !void {
    if (std.mem.eql(u8, val, "NULL") or std.mem.eql(u8, val, "null")) {
        try w.writeAll("null");
    } else if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "TRUE")) {
        try w.writeAll("true");
    } else if (std.mem.eql(u8, val, "false") or std.mem.eql(u8, val, "FALSE")) {
        try w.writeAll("false");
    } else if (std.fmt.parseInt(i64, val, 10)) |num| {
        try w.print("{d}", .{num});
    } else |_| {
        if (std.fmt.parseFloat(f64, val)) |num| {
            try w.print("{d}", .{num});
        } else |_| {
            try w.writeAll("\"");
            const utils = @import("../utils.zig");
            try utils.jsonEscapeString(w, val);
            try w.writeAll("\"");
        }
    }
}

// ─── FK Reference Lookup ──────────────────────────────────────

pub fn findFkRefTable(col_name: []const u8, fks: []const FkDecl) ?[]const u8 {
    for (fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col_name)) {
            return fk.ref_table;
        }
    }
    return null;
}

// ─── Name Helpers ─────────────────────────────────────────────

/// Strip trailing 's' for a simple singular form. Used by GraphQL and Prisma generators.
pub fn toCamelSingular(name: []const u8) []const u8 {
    if (name.len == 0) return name;
    if (name[name.len - 1] == 's' and name.len > 1) {
        return name[0 .. name.len - 1];
    }
    return name;
}
