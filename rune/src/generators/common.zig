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

/// Check if any table in the AST has at least one enum column.
/// Used by drizzle and prisma generators to determine if enum definitions are needed.
pub fn hasAnyEnums(typed: typed_ast.TypedAst) bool {
    for (typed.tables) |table| {
        for (table.columns) |col| {
            if (col.flags.is_enum) return true;
        }
    }
    return false;
}

/// Check if any table in the AST has at least one composite (multi-column) FK.
/// Used by drizzle generator to determine if foreignKey import is needed.
pub fn hasAnyCompositeFks(typed: typed_ast.TypedAst) bool {
    for (typed.tables) |table| {
        if (tableHasCompositeFks(table)) return true;
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

// ─── ORM Default Value Writer ───────────────────────────────────
// Eliminates duplicated default value emission across ORM generators.
// Pattern: prefix + formatted_default + suffix (e.g. ".default(", ")")

/// Write a formatted default value with prefix and suffix wrappers.
/// Used by drizzle (.default()), knex (.defaultTo()), prisma (@default()),
/// sqlalchemy (server_default=), typeorm (default:).
pub fn writeOrmDefault(
    w: *std.Io.Writer,
    dflt: []const u8,
    prefix: []const u8,
    suffix: []const u8,
    orm_target: OrmTarget,
) !void {
    if (shouldEmitDefault(dflt)) {
        try w.writeAll(prefix);
        try writeFormattedDefault(w, dflt, getOrmFormatter(orm_target));
        try w.writeAll(suffix);
    }
}

// ─── Import Tracker ─────────────────────────────────────────────
// Shared import tracking for ORM generators.
// Eliminates ~80 lines of duplicated boolean-flag logic.

pub const ImportTracker = struct {
    need_integer: bool = false,
    need_smallint: bool = false,
    need_bigint: bool = false,
    need_varchar: bool = false,
    need_text: bool = false,
    need_boolean: bool = false,
    need_timestamp: bool = false,
    need_date: bool = false,
    need_json: bool = false,
    need_uuid: bool = false,
    need_decimal: bool = false,
    need_blob: bool = false,
    need_serial: bool = false,
    need_enum: bool = false,
    has_any_index: bool = false,
    has_unique_index: bool = false,
    has_composite_index: bool = false,
    has_any_fk: bool = false,
    has_composite_fk: bool = false,

    /// Scan a typed AST to populate import flags.
    pub fn scan(typed: typed_ast.TypedAst) ImportTracker {
        var tracker = ImportTracker{};
        for (typed.tables) |table| {
            tracker.scanTable(table);
        }
        return tracker;
    }

    /// Scan a single table's columns, indexes, and FKs.
    pub fn scanTable(self: *ImportTracker, table: typed_ast.TypedTable) void {
        for (table.columns) |col| {
            self.scanColumn(col);
        }
        for (table.indexes) |idx| {
            if (idx.kind == .primary_key) continue;
            self.has_any_index = true;
            if (idx.kind == .unique) self.has_unique_index = true;
            if (idx.fields.len > 1) self.has_composite_index = true;
        }
        for (table.fks) |fk| {
            self.has_any_fk = true;
            if (fk.fields.len > 1) self.has_composite_fk = true;
        }
    }

    /// Scan a single column to update type flags.
    pub fn scanColumn(self: *ImportTracker, col: typed_ast.TypedColumn) void {
        if (col.flags.is_enum) self.need_enum = true;
        switch (col.sql_type) {
            .int => self.need_integer = true,
            .serial => self.need_serial = true,
            .smallint => self.need_smallint = true,
            .bigint => self.need_bigint = true,
            .decimal => self.need_decimal = true,
            .varchar => self.need_varchar = true,
            .text => self.need_text = true,
            .boolean => self.need_boolean = true,
            .datetime, .timestamptz => self.need_timestamp = true,
            .date => self.need_date = true,
            .json, .jsonb => self.need_json = true,
            .uuid => self.need_uuid = true,
            .blob => self.need_blob = true,
            .inet => self.need_varchar = true,
            .enum_values => self.need_enum = true,
            .raw_sql, .passthrough => self.need_text = true,
        }
    }
};

// ─── Shared SQL Type-to-String Writer ─────────────────────────
// Eliminates duplicated SQL type rendering across generators.
// Used by docs.zig, symbol_index.zig, and potentially others.

const SqlType = @import("../types/sql_type.zig").SqlType;

/// Write a human-readable SQL type string.
/// When `uppercase` is true, outputs UPPERCASE (INT, VARCHAR(64)).
/// When `uppercase` is false, outputs lowercase (int, varchar(64)).
pub fn writeSqlTypeString(w: *std.Io.Writer, sql_type: SqlType, uppercase: bool) !void {
    switch (sql_type) {
        .int => try w.writeAll(if (uppercase) "INT" else "int"),
        .bigint => try w.writeAll(if (uppercase) "BIGINT" else "bigint"),
        .smallint => try w.writeAll(if (uppercase) "SMALLINT" else "smallint"),
        .decimal => |ds| {
            if (uppercase) {
                try w.print("DECIMAL({d},{d})", .{ ds.precision, ds.scale });
            } else {
                try w.print("decimal({d},{d})", .{ ds.precision, ds.scale });
            }
        },
        .varchar => |n| {
            if (n > 0) {
                if (uppercase) {
                    try w.print("VARCHAR({d})", .{n});
                } else {
                    try w.print("varchar({d})", .{n});
                }
            } else {
                try w.writeAll(if (uppercase) "TEXT" else "text");
            }
        },
        .text => try w.writeAll(if (uppercase) "TEXT" else "text"),
        .blob => try w.writeAll(if (uppercase) "BLOB" else "blob"),
        .json => try w.writeAll(if (uppercase) "JSON" else "json"),
        .jsonb => try w.writeAll(if (uppercase) "JSONB" else "jsonb"),
        .datetime => try w.writeAll(if (uppercase) "DATETIME" else "datetime"),
        .date => try w.writeAll(if (uppercase) "DATE" else "date"),
        .timestamptz => try w.writeAll(if (uppercase) "TIMESTAMPTZ" else "timestamptz"),
        .boolean => try w.writeAll(if (uppercase) "BOOLEAN" else "boolean"),
        .uuid => try w.writeAll(if (uppercase) "UUID" else "uuid"),
        .inet => try w.writeAll(if (uppercase) "INET" else "inet"),
        .serial => try w.writeAll(if (uppercase) "SERIAL" else "serial"),
        .enum_values => |vals| {
            if (uppercase) {
                try w.writeAll("ENUM(");
            } else {
                try w.writeAll("enum(");
            }
            for (vals, 0..) |v, vi| {
                if (vi > 0) try w.writeAll(", ");
                if (uppercase) {
                    try w.print("'{s}'", .{v});
                } else {
                    try w.print("{s}", .{v});
                }
            }
            try w.writeAll(")");
        },
        .raw_sql => |s| try w.writeAll(s),
        .passthrough => |s| try w.writeAll(s),
    }
}

// ─── Default Value Guards ─────────────────────────────────────

/// Check if a default value should be emitted in ORM output.
/// Returns true if the default is non-empty and not the literal "null".
pub fn shouldEmitDefault(dflt: []const u8) bool {
    return dflt.len > 0 and !std.mem.eql(u8, dflt, "null");
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

/// SQL spelling of an FkActionType for ON DELETE / ON UPDATE clauses.
pub fn fkActionSql(action: ast_mod.FkActionType) []const u8 {
    return switch (action) {
        .cascade => "CASCADE",
        .set_null => "SET NULL",
        .set_default => "SET DEFAULT",
        .restrict => "RESTRICT",
        .no_action => "NO ACTION",
    };
}

/// Lowercase spelling for JS option objects (`onDelete: 'set null'`).
pub fn fkActionSqlLower(action: ast_mod.FkActionType) []const u8 {
    return switch (action) {
        .cascade => "cascade",
        .set_null => "set null",
        .set_default => "set default",
        .restrict => "restrict",
        .no_action => "no action",
    };
}

/// Write `onDelete`/`onUpdate` option entries (JS object style, e.g. for
/// drizzle's foreignKey({ onDelete: 'cascade' })) — comma-separated, no braces.
pub fn writeJsFkActions(w: *std.Io.Writer, actions: []const @import("../types/ast.zig").FkAction) !void {
    for (actions) |a| {
        const key = switch (a.trigger) {
            .on_delete => "onDelete",
            .on_update => "onUpdate",
        };
        const val = switch (a.action) {
            .cascade => "cascade",
            .set_null => "set null",
            .set_default => "set default",
            .restrict => "restrict",
            .no_action => "no action",
        };
        try w.print(", {s}: '{s}'", .{ key, val });
    }
}

// ─── Shared Enum Value Writer ─────────────────────────────────
// Eliminates duplicated enum value iteration across ORM generators.

/// Write comma-separated single-quoted enum values.
/// Used by drizzle, typeorm, sqlalchemy generators for enum definitions.
/// Pattern: 'val1', 'val2', 'val3'
pub fn writeEnumValues(w: *std.Io.Writer, values: []const []const u8) !void {
    for (values, 0..) |val, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{val});
    }
}

// ─── Shared Comment Writer ────────────────────────────────────
// Eliminates duplicated comment emission across ORM generators.

/// Write a comment line if the comment exists and is non-empty.
/// `prefix` is the comment syntax (e.g. "//", "#", "--").
/// `indent` is optional indentation before the prefix.
pub fn writeComment(w: *std.Io.Writer, comment: ?[]const u8, prefix: []const u8, indent: []const u8) !void {
    if (comment) |c| {
        if (c.len > 0) {
            try w.print("{s}{s} {s}\n", .{ indent, prefix, c });
        }
    }
}

// ─── Shared Field List Writer ─────────────────────────────────
// Eliminates duplicated field list iteration across ORM generators.

/// Write a comma-separated list of single-quoted field names.
/// Used by drizzle, typeorm, knex for index/FK field lists.
/// Pattern: 'field1', 'field2', 'field3'
pub fn writeFieldList(w: *std.Io.Writer, fields: []const []const u8) !void {
    for (fields, 0..) |field, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{field});
    }
}

// ─── Name Helpers ─────────────────────────────────────────────

/// Irregular plural → singular mappings.
const irregulars = [_]struct { from: []const u8, to: []const u8 }{
    .{ .from = "men", .to = "man" },
    .{ .from = "women", .to = "woman" },
    .{ .from = "children", .to = "child" },
    .{ .from = "people", .to = "person" },
    .{ .from = "mice", .to = "mouse" },
    .{ .from = "geese", .to = "goose" },
    .{ .from = "criteria", .to = "criterion" },
    .{ .from = "phenomena", .to = "phenomenon" },
    .{ .from = "data", .to = "datum" },
};

/// Convert plural table name to singular form for ORM generators.
/// Handles irregular plurals (categories→category, statuses→status, men→man, etc.).
/// The allocator is used for cases that require creating a new string (-ies→-y).
pub fn toCamelSingular(alloc: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (name.len == 0) return name;

    // Check irregular plurals first
    for (irregulars) |pair| {
        if (std.mem.eql(u8, name, pair.from)) return pair.to;
    }

    // -ies → -y (e.g. categories→category, companies→company)
    if (name.len > 3 and std.mem.eql(u8, name[name.len - 3 ..], "ies")) {
        return try std.fmt.allocPrint(alloc, "{s}y", .{name[0 .. name.len - 3]});
    }

    // -ses, -xes, -zes, -ches, -shes → strip "es"
    if (name.len > 2) {
        const last2 = name[name.len - 2 ..];
        if (std.mem.eql(u8, last2, "es")) {
            const penult = name[name.len - 3];
            if (penult == 's' or penult == 'x' or penult == 'z' or penult == 'h') {
                // Handle doubled consonants: quizzes→quiz (strip "zes"), addresses→address (strip "es")
                // If the char before penult matches penult, the consonant was doubled → strip one more
                if (name.len >= 4 and name[name.len - 4] == penult) {
                    // For "quizzes" (len=7): name[0..4] = "quiz" ✓
                    // For "addresses" (len=9): penult='s', name[5]='s' → strip to name[0..6] = "addres" ✗
                    // Only strip extra for non-'s' penult to avoid address issue
                    if (penult != 's') {
                        return name[0 .. name.len - 3];
                    }
                }
                return name[0 .. name.len - 2];
            }
        }
    }

    // -ves → -f (e.g. knives→knife, lives→life, wives→wife)
    if (name.len > 3 and std.mem.eql(u8, name[name.len - 3 ..], "ves")) {
        return name[0 .. name.len - 3];
    }

    // Default: strip trailing 's' if present and name is > 1 char
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
                        defer alloc.free(items);
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

// ─── Shared JSON Table Schema Writer ──────────────────────────

/// Write a JSON Schema / OpenAPI table definition.
/// Shared by `json_schema.zig` and `openapi.zig` to eliminate duplication.
/// - `indent`: table-level indentation (e.g. "    " for json_schema, "      " for openapi)
/// - `ref_prefix`: FK $ref path prefix (e.g. "#/$defs/" or "#/components/schemas/")
pub fn writeTableSchemaJson(
    alloc: std.mem.Allocator,
    w: *std.Io.Writer,
    table: typed_ast.TypedTable,
    indent: []const u8,
    ref_prefix: []const u8,
) !void {
    const prop_indent = try std.fmt.allocPrint(alloc, "{s}  ", .{indent});
    defer alloc.free(prop_indent);

    const col_indent = try std.fmt.allocPrint(alloc, "{s}    ", .{indent});
    defer alloc.free(col_indent);

    try w.print("{s}\"{s}\": {{\n", .{ indent, table.name });
    try w.print("{s}  \"type\": \"object\",\n", .{indent});

    // Description from comment
    if (table.comment) |c| {
        if (c.len > 0) {
            try w.print("{s}  \"description\": \"", .{indent});
            try utils.jsonEscapeString(w, c);
            try w.writeAll("\",\n");
        }
    }

    // Properties
    try w.print("{s}  \"properties\": {{\n", .{indent});
    for (table.columns, 0..) |col, ci| {
        if (ci > 0) try w.writeAll(",\n");
        try writeColumnPropJson(alloc, w, col, table, col_indent, ref_prefix);
    }
    if (table.columns.len > 0) try w.writeAll("\n");
    try w.print("{s}  }},\n", .{indent});

    // Required: non-nullable columns, except those the database fills in —
    // a datetime with `+` has DEFAULT CURRENT_TIMESTAMP, so requiring the
    // client to supply it would make every insert fail validation.
    try w.print("{s}  \"required\": [", .{indent});
    var first = true;
    for (table.columns) |col| {
        if (!col.flags.nullable and !col.flags.has_timestamp_default) {
            if (!first) try w.writeAll(", ");
            first = false;
            try w.print("\"{s}\"", .{col.name});
        }
    }
    try w.writeAll("],\n");

    // Additional properties: false
    try w.print("{s}  \"additionalProperties\": false\n", .{indent});

    try w.print("{s}}}", .{indent});
}
