const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const utils = @import("../utils.zig");
const Writer = std.Io.Writer;

// ─── JSON Schema Generator ──────────────────────────────────────
// Enhanced JSON Schema draft-07 output from TypedAst.
// Output: JSON Schema with $defs, $ref, proper required arrays.
//
// Architecture: TypedAst → JSON Schema
//   $defs: each table → reusable object definition
//   properties: top-level object with table $ref or inline
//   Each column → property with type from SqlType.toJsonSchema()
//   Non-nullable → required array
//   Comment → description
//   Enum values → enum array or $ref to named definition
//   FK columns → $ref to referenced table's definition

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: @import("../dialect/enum.zig").Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");
    try w.writeAll("  \"$schema\": \"http://json-schema.org/draft-07/schema#\",\n");

    // Title from schema name
    if (typed.schema_name) |name| {
        try w.print("  \"title\": \"{s}\",\n", .{name});
    } else {
        try w.writeAll("  \"title\": \"rune-schema\",\n");
    }

    try w.writeAll("  \"type\": \"object\",\n");

    // $defs section — reusable table definitions
    if (typed.tables.len > 0) {
        try w.writeAll("  \"$defs\": {\n");
        for (typed.tables, 0..) |table, ti| {
            if (ti > 0) try w.writeAll(",\n");
            try writeTableDef(alloc, w, table);
        }
        try w.writeAll("\n  },\n");
    }

    // Top-level properties — each table as $ref to its definition
    try w.writeAll("  \"properties\": {\n");
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll(",\n");
        try w.print("    \"{s}\": {{ \"$ref\": \"#/$defs/{s}\" }}", .{ table.name, table.name });
    }
    if (typed.tables.len > 0) try w.writeAll("\n");
    try w.writeAll("  },\n");

    // Top-level required: all tables are required
    try w.writeAll("  \"required\": [");
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll(", ");
        try w.print("\"{s}\"", .{table.name});
    }
    try w.writeAll("]\n");

    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Table Definition (in $defs) ────────────────────────────────

fn writeTableDef(alloc: std.mem.Allocator, w: *Writer, table: typed_ast.TypedTable) !void {
    try w.print("    \"{s}\": {{\n", .{table.name});
    try w.writeAll("      \"type\": \"object\",\n");

    // Description from comment
    if (table.comment) |c| {
        if (c.len > 0) {
            try w.writeAll("      \"description\": \"");
            try utils.jsonEscapeString(w, c);
            try w.writeAll("\",\n");
        }
    }

    // Properties
    try w.writeAll("      \"properties\": {\n");
    for (table.columns, 0..) |col, ci| {
        if (ci > 0) try w.writeAll(",\n");
        try writeColumnProp(alloc, w, col, table);
    }
    if (table.columns.len > 0) try w.writeAll("\n");
    try w.writeAll("      },\n");

    // Required: non-nullable columns
    try w.writeAll("      \"required\": [");
    var first = true;
    for (table.columns) |col| {
        if (!col.flags.nullable) {
            if (!first) try w.writeAll(", ");
            first = false;
            try w.print("\"{s}\"", .{col.name});
        }
    }
    try w.writeAll("],\n");

    // Additional properties: false
    try w.writeAll("      \"additionalProperties\": false\n");

    try w.writeAll("    }");
}

// ─── Column Property ────────────────────────────────────────────

fn writeColumnProp(alloc: std.mem.Allocator, w: *Writer, col: typed_ast.TypedColumn, table: typed_ast.TypedTable) !void {
    try w.print("        \"{s}\": ", .{col.name});

    // Check if this column has an FK reference — emit $ref
    const fk_ref_table: ?[]const u8 = blk: {
        for (table.fks) |fk| {
            if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col.name)) {
                break :blk fk.ref_table;
            }
        }
        break :blk null;
    };

    if (fk_ref_table) |ref_table| {
        // FK column: emit $ref to referenced table with type wrapper
        try w.writeAll("{\n");
        try w.print("          \"$ref\": \"#/$defs/{s}\",\n", .{ref_table});
        try w.writeAll("          \"description\": \"Foreign key to ");
        try w.writeAll(ref_table);
        try w.writeAll("\"\n");
        try w.writeAll("        }");
    } else {
        // Regular column: emit type from SqlType.toJsonSchema()
        try col.sql_type.toJsonSchema(w);

        // Add CHECK constraint metadata
        if (col.check) |check| {
            switch (check.kind) {
                .range, .range_upper_exclusive, .range_lower_exclusive, .range_both_exclusive => {
                    if (parseRange(check.expr)) |range| {
                        try w.writeAll(",\n");
                        if (range.min) |min| {
                            try w.print("          \"minimum\": {d}", .{min});
                            if (range.max) |max| {
                                try w.writeAll(",\n");
                                try w.print("          \"maximum\": {d}", .{max});
                            }
                        } else if (range.max) |max| {
                            try w.print("          \"maximum\": {d}", .{max});
                        }
                    }
                },
                .comparison => {
                    if (parseComparison(check.expr)) |cmp| {
                        try w.writeAll(",\n");
                        if (cmp.op[0] == '>') {
                            try w.print("          \"exclusiveMinimum\": {d}", .{cmp.value});
                        } else if (cmp.op[0] == '<') {
                            try w.print("          \"exclusiveMaximum\": {d}", .{cmp.value});
                        }
                    }
                },
                .in_list => {
                    if (parseInList(alloc, check.expr)) |items| {
                        try w.writeAll(",\n          \"enum\": [");
                        for (items, 0..) |item, ii| {
                            if (ii > 0) try w.writeAll(", ");
                            try w.print("\"{s}\"", .{item});
                        }
                        try w.writeAll("]");
                    }
                },
            }
        }

        // Add default value
        if (col.default) |def| {
            if (def.len > 0) {
                try w.writeAll(",\n          \"default\": ");
                try writeJsonValue(w, def);
            }
        }

        // Add description from column comment
        if (col.comment) |c| {
            if (c.len > 0) {
                try w.writeAll(",\n          \"description\": \"");
                try utils.jsonEscapeString(w, c);
                try w.writeAll("\"");
            }
        }
    }
}

fn writeJsonValue(w: *Writer, val: []const u8) !void {
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

// ─── CHECK Constraint Parsers ──────────────────────────────────

const Range = struct {
    min: ?i64,
    max: ?i64,
};

fn parseRange(expr: []const u8) ?Range {
    var min_val: ?i64 = null;
    var max_val: ?i64 = null;

    var i: usize = 0;
    while (i < expr.len) {
        if (i + 1 < expr.len and expr[i] == '>' and expr[i + 1] == '=') {
            const num_start = i + 2;
            var num_end = num_start;
            if (num_end < expr.len and expr[num_end] == '-') num_end += 1;
            while (num_end < expr.len and (expr[num_end] >= '0' and expr[num_end] <= '9')) {
                num_end += 1;
            }
            if (num_end > num_start) {
                if (std.fmt.parseInt(i64, expr[num_start..num_end], 10)) |num| {
                    min_val = num;
                } else |_| {}
            }
            i = num_end;
        } else if (i + 1 < expr.len and expr[i] == '<' and expr[i + 1] == '=') {
            const num_start = i + 2;
            var num_end = num_start;
            if (num_end < expr.len and expr[num_end] == '-') num_end += 1;
            while (num_end < expr.len and (expr[num_end] >= '0' and expr[num_end] <= '9')) {
                num_end += 1;
            }
            if (num_end > num_start) {
                if (std.fmt.parseInt(i64, expr[num_start..num_end], 10)) |num| {
                    max_val = num;
                } else |_| {}
            }
            i = num_end;
        } else {
            i += 1;
        }
    }

    if (min_val != null or max_val != null) {
        return .{ .min = min_val, .max = max_val };
    }
    return null;
}

const Comparison = struct {
    op: []const u8,
    value: i64,
};

fn parseComparison(expr: []const u8) ?Comparison {
    var i: usize = 0;
    while (i < expr.len and expr[i] == ' ') : (i += 1) {}

    if (i < expr.len and (expr[i] == '>' or expr[i] == '<' or expr[i] == '=')) {
        const op_start = i;
        i += 1;
        if (i < expr.len and expr[i] == '=') i += 1;
        const op = expr[op_start..i];

        while (i < expr.len and expr[i] == ' ') : (i += 1) {}

        const num_start = i;
        if (i < expr.len and expr[i] == '-') i += 1;
        while (i < expr.len and ((expr[i] >= '0' and expr[i] <= '9') or expr[i] == '.')) {
            i += 1;
        }
        if (i > num_start) {
            if (std.fmt.parseInt(i64, expr[num_start..i], 10)) |num| {
                return .{ .op = op, .value = num };
            } else |_| {}
        }
    }
    return null;
}

fn parseInList(alloc: std.mem.Allocator, expr: []const u8) ?[]const []const u8 {
    const trimmed = std.mem.trim(u8, expr, " ");
    if (trimmed.len < 2) return null;

    const inner = if (trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')')
        trimmed[1 .. trimmed.len - 1]
    else
        trimmed;

    var items = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return null;
    var start: usize = 0;
    var in_quote = false;
    var i: usize = 0;

    while (i < inner.len) {
        if (inner[i] == '\'') {
            if (in_quote) {
                const item = std.mem.trim(u8, inner[start..i], " '");
                items.append(alloc, item) catch {
                    items.deinit(alloc);
                    return null;
                };
                in_quote = false;
                start = i + 1;
            } else {
                in_quote = true;
                start = i + 1;
            }
        } else if (inner[i] == ',' and !in_quote) {
            const item = std.mem.trim(u8, inner[start..i], " ");
            if (item.len > 0) {
                items.append(alloc, item) catch {
                    items.deinit(alloc);
                    return null;
                };
            }
            start = i + 1;
        }
        i += 1;
    }

    if (start < inner.len) {
        const item = std.mem.trim(u8, inner[start..], " '");
        if (item.len > 0) {
            items.append(alloc, item) catch {
                items.deinit(alloc);
                return null;
            };
        }
    }

    if (items.items.len == 0) {
        items.deinit(alloc);
        return null;
    }

    return items.toOwnedSlice(alloc) catch {
        items.deinit(alloc);
        return null;
    };
}
