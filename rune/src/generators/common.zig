const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const utils = @import("../utils.zig");
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

// ─── Shared JSON Column Property Writer ────────────────────────

/// Write a JSON Schema / OpenAPI property for a column.
/// Shared by `json_schema.zig` and `openapi.zig` to eliminate duplication.
/// - `indent`: outer indentation (e.g. "        " for json_schema, "          " for openapi)
/// - `ref_prefix`: FK $ref path prefix (e.g. "#/$defs/" or "#/components/schemas/")
pub fn writeColumnPropJson(
    alloc: std.mem.Allocator,
    w: *std.Io.Writer,
    col: typed_ast.TypedColumn,
    table: typed_ast.TypedTable,
    indent: []const u8,
    ref_prefix: []const u8,
) !void {
    try w.print("{s}\"{s}\": ", .{ indent, col.name });

    const fk_ref_table = findFkRefTable(col.name, table.fks);

    if (fk_ref_table) |ref_table| {
        try w.writeAll("{\n");
        try w.print("{s}  \"$ref\": \"{s}{s}\",\n", .{ indent, ref_prefix, ref_table });
        try w.print("{s}  \"description\": \"Foreign key to ", .{indent});
        try w.writeAll(ref_table);
        try w.writeAll("\"\n");
        try w.print("{s}}}", .{indent});
    } else {
        try col.sql_type.toJsonSchema(w);

        if (col.check) |check| {
            switch (check.kind) {
                .range, .range_upper_exclusive, .range_lower_exclusive, .range_both_exclusive => {
                    if (parseRange(check.expr)) |range| {
                        try w.writeAll(",\n");
                        if (range.min) |min| {
                            try w.print("{s}  \"minimum\": {d}", .{ indent, min });
                            if (range.max) |max| {
                                try w.writeAll(",\n");
                                try w.print("{s}  \"maximum\": {d}", .{ indent, max });
                            }
                        } else if (range.max) |max| {
                            try w.print("{s}  \"maximum\": {d}", .{ indent, max });
                        }
                    }
                },
                .comparison => {
                    if (parseComparison(check.expr)) |cmp| {
                        try w.writeAll(",\n");
                        if (cmp.op[0] == '>') {
                            try w.print("{s}  \"exclusiveMinimum\": {d}", .{ indent, cmp.value });
                        } else if (cmp.op[0] == '<') {
                            try w.print("{s}  \"exclusiveMaximum\": {d}", .{ indent, cmp.value });
                        }
                    }
                },
                .in_list => {
                    if (parseInList(alloc, check.expr)) |items| {
                        try w.writeAll(",\n");
                        try w.print("{s}  \"enum\": [", .{indent});
                        for (items, 0..) |item, ii| {
                            if (ii > 0) try w.writeAll(", ");
                            try w.print("\"{s}\"", .{item});
                        }
                        try w.writeAll("]");
                    }
                },
            }
        }

        if (col.default) |def| {
            if (def.len > 0) {
                try w.writeAll(",\n");
                try w.print("{s}  \"default\": ", .{indent});
                try writeJsonValue(w, def);
            }
        }

        if (col.comment) |c| {
            if (c.len > 0) {
                try w.writeAll(",\n");
                try w.print("{s}  \"description\": \"", .{indent});
                try utils.jsonEscapeString(w, c);
                try w.writeAll("\"");
            }
        }
    }
}
