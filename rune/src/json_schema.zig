const std = @import("std");
const typed_ast = @import("types/typed_ast.zig");
const sql_type_mod = @import("types/sql_type.zig");
const utils = @import("utils.zig");
const Writer = std.Io.Writer;

// ─── JSON Schema Generator ──────────────────────────────────
// Consumes TypedAst directly (no SQL dialect needed).
// Output: JSON Schema draft-07 document.
//
// Architecture: TypedAst → JSON Schema
//   Each table → object property
//   Each column → property with type from SqlType.toJsonSchema()
//   Non-nullable → required array
//   Comment → description
//   Enum values → enum array

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst) ![]const u8 {
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
    try w.writeAll("  \"properties\": {\n");

    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll(",\n");
        try writeTable(alloc, w, table);
    }

    if (typed.tables.len > 0) try w.writeAll("\n");
    try w.writeAll("  }\n");
    try w.writeAll("}\n");

    try w.flush();
    var out = aw.toArrayList();
    return try out.toOwnedSlice(alloc);
}

fn writeTable(alloc: std.mem.Allocator, w: *Writer, table: typed_ast.TypedTable) !void {
    _ = alloc;
    try w.print("    \"{s}\": {{\n", .{table.name});
    try w.writeAll("      \"type\": \"object\",\n");

    // Description from comment (with JSON-safe escaping)
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
        try w.print("        \"{s}\": ", .{col.name});
        try col.sql_type.toJsonSchema(w);

        // Add CHECK constraint metadata
        if (col.check) |check| {
            switch (check.kind) {
                .range, .range_upper_exclusive, .range_lower_exclusive, .range_both_exclusive => {
                    // Parse range from expression like "age >= 0 AND age <= 150"
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
                    // Parse comparison like "> 0" or "< 100"
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
                    // Parse IN list like "a,b,c"
                    if (parseInList(check.expr)) |items| {
                        try w.writeAll(",\n          \"enum\": [");
                        for (items, 0..) |item, ii| {
                            if (ii > 0) try w.writeAll(",");
                            try w.print("\"{s}\"", .{item});
                        }
                        try w.writeAll("]");
                    }
                },
            }
        }

        // Add default value
        if (col.default) |def| {
            try w.writeAll(",\n          \"default\": ");
            // Try to parse as number, otherwise treat as string
            if (std.fmt.parseInt(i64, def, 10)) |num| {
                try w.print("{d}", .{num});
            } else |_| {
                if (std.fmt.parseFloat(f64, def)) |num| {
                    try w.print("{d}", .{num});
                } else |_| {
                    try w.writeAll("\"");
                    try utils.jsonEscapeString(w, def);
                    try w.writeAll("\"");
                }
            }
        }
    }
    if (table.columns.len > 0) try w.writeAll("\n");
    try w.writeAll("      },\n");

    // Required: non-nullable columns
    try w.writeAll("      \"required\": [");
    var first = true;
    for (table.columns) |col| {
        if (!col.flags.nullable) {
            if (!first) try w.writeAll(",");
            first = false;
            try w.print("\"{s}\"", .{col.name});
        }
    }
    try w.writeAll("]\n");

    try w.writeAll("    }");
}

// ─── CHECK Constraint Parsers ──────────────────────────────────

const Range = struct {
    min: ?i64,
    max: ?i64,
};

fn parseRange(expr: []const u8) ?Range {
    // Simple parser for expressions like "age >= 0 AND age <= 150"
    // or "0 <= age AND age <= 150"
    var min_val: ?i64 = null;
    var max_val: ?i64 = null;

    // Look for patterns like ">= N" or "<= N"
    var i: usize = 0;
    while (i < expr.len) {
        if (i + 1 < expr.len and expr[i] == '>' and expr[i + 1] == '=') {
            // Found >=, parse number after
            const num_start = i + 2;
            var num_end = num_start;
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
            // Found <=, parse number after
            const num_start = i + 2;
            var num_end = num_start;
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
    // Parse expressions like "> 0" or "< 100"
    var i: usize = 0;
    while (i < expr.len and expr[i] == ' ') : (i += 1) {}

    if (i < expr.len and (expr[i] == '>' or expr[i] == '<' or expr[i] == '=')) {
        const op_start = i;
        i += 1;
        if (i < expr.len and expr[i] == '=') i += 1;
        const op = expr[op_start..i];

        while (i < expr.len and expr[i] == ' ') : (i += 1) {}

        const num_start = i;
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

fn parseInList(expr: []const u8) ?[]const []const u8 {
    // This is a simplified parser - in real code you'd want proper allocation
    // For now, return null as IN lists are complex to parse without allocation
    _ = expr;
    return null;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

fn makeTestColumn(name: []const u8, sql_type: sql_type_mod.SqlType) typed_ast.TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type,
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 1,
    };
}

test "json_schema: int column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("id", .int);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"integer\"}", result);
}

test "json_schema: varchar column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("name", .{ .varchar = 64 });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"string\",\"maxLength\":64}", result);
}

test "json_schema: boolean column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("active", .boolean);
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expectEqualStrings("{\"type\":\"boolean\"}", result);
}

test "json_schema: enum column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const vals = try alloc.dupe([]const u8, &.{ "active", "inactive", "banned" });
    const col = makeTestColumn("status", .{ .enum_values = vals });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expect(std.mem.indexOf(u8, result, "\"enum\":[\"active\",\"inactive\",\"banned\"]") != null);
}

test "json_schema: decimal column" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const col = makeTestColumn("price", .{ .decimal = .{ .precision = 10, .scale = 2 } });
    try col.sql_type.toJsonSchema(w);
    try w.flush();
    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\":\"number\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"multipleOf\"") != null);
}
