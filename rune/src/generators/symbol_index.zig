const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── Symbol Index Generator ─────────────────────────────────────
// Generates a JSON index of all tables, fields, types, and their
// locations for IDE integration and tooling.

pub fn generate(alloc: std.mem.Allocator, ast: typed_ast.TypedAst, dialect: Dialect) ![]const u8 {
    _ = dialect; // symbol index is dialect-agnostic

    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n  \"schema\": ");
    if (ast.schema_name) |name| {
        try w.print("\"{s}\"", .{name});
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\n  \"tables\": [\n");

    for (ast.tables, 0..) |table, table_idx| {
        try w.print("    {{\n      \"name\": \"{s}\",\n      \"line\": {d},\n", .{ table.name, table.line_no });

        if (table.comment) |comment| {
            try w.print("      \"comment\": \"{s}\",\n", .{comment});
        }

        try w.writeAll("      \"columns\": [\n");
        for (table.columns, 0..) |col, col_idx| {
            try w.print("        {{ \"name\": \"{s}\", \"type\": \"", .{col.name});
            try writeSqlType(w, col.sql_type);
            try w.writeAll("\"");
            if (col.comment) |comment| {
                try w.print(", \"comment\": \"{s}\"", .{comment});
            }
            if (col.flags.primary_key) {
                try w.writeAll(", \"primaryKey\": true");
            }
            if (col.flags.nullable) {
                try w.writeAll(", \"nullable\": true");
            }
            if (col.flags.auto_increment) {
                try w.writeAll(", \"autoIncrement\": true");
            }
            try w.writeAll(" }");
            if (col_idx < table.columns.len - 1) try w.writeAll(",");
            try w.writeAll("\n");
        }
        try w.writeAll("      ],\n");

        // Foreign keys
        if (table.fks.len > 0) {
            try w.writeAll("      \"foreignKeys\": [\n");
            for (table.fks, 0..) |fk, fk_idx| {
                try w.writeAll("        { \"fields\": [");
                for (fk.fields, 0..) |field, field_idx| {
                    try w.print("\"{s}\"", .{field});
                    if (field_idx < fk.fields.len - 1) try w.writeAll(", ");
                }
                try w.print("], \"references\": {{ \"table\": \"{s}\", \"fields\": [", .{fk.ref_table});
                for (fk.ref_fields, 0..) |ref_field, ref_idx| {
                    try w.print("\"{s}\"", .{ref_field});
                    if (ref_idx < fk.ref_fields.len - 1) try w.writeAll(", ");
                }
                try w.writeAll("] } }");
                if (fk_idx < table.fks.len - 1) try w.writeAll(",");
                try w.writeAll("\n");
            }
            try w.writeAll("      ],\n");
        }

        // Indexes
        if (table.indexes.len > 0) {
            try w.writeAll("      \"indexes\": [\n");
            for (table.indexes, 0..) |idx, idx_idx| {
                try w.print("        {{ \"name\": \"{s}\", \"fields\": [", .{idx.name});
                for (idx.fields, 0..) |field, field_idx| {
                    try w.print("\"{s}\"", .{field});
                    if (field_idx < idx.fields.len - 1) try w.writeAll(", ");
                }
                try w.writeAll("]");
                if (idx.kind == .unique) {
                    try w.writeAll(", \"unique\": true");
                }
                try w.writeAll(" }");
                if (idx_idx < table.indexes.len - 1) try w.writeAll(",");
                try w.writeAll("\n");
            }
            try w.writeAll("      ],\n");
        }

        try w.writeAll("      \"fieldCount\": ");
        try w.print("{d}", .{table.columns.len});
        try w.writeAll("\n    }");
        if (table_idx < ast.tables.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }

    try w.writeAll("  ],\n");
    try w.print("  \"tableCount\": {d}\n", .{ast.tables.len});
    try w.writeAll("}\n");

    return try aw.toOwnedSlice();
}

fn writeSqlType(w: anytype, sql_type: sql_type_mod.SqlType) !void {
    switch (sql_type) {
        .int => try w.writeAll("int"),
        .bigint => try w.writeAll("bigint"),
        .smallint => try w.writeAll("smallint"),
        .decimal => |d| try w.print("decimal({d},{d})", .{ d.precision, d.scale }),
        .varchar => |len| {
            if (len > 0) {
                try w.print("varchar({d})", .{len});
            } else {
                try w.writeAll("text");
            }
        },
        .text => try w.writeAll("text"),
        .blob => try w.writeAll("blob"),
        .json => try w.writeAll("json"),
        .jsonb => try w.writeAll("jsonb"),
        .datetime => try w.writeAll("datetime"),
        .date => try w.writeAll("date"),
        .timestamptz => try w.writeAll("timestamptz"),
        .boolean => try w.writeAll("boolean"),
        .uuid => try w.writeAll("uuid"),
        .inet => try w.writeAll("inet"),
        .serial => try w.writeAll("serial"),
        .enum_values => |vals| {
            try w.writeAll("enum(");
            for (vals, 0..) |val, i| {
                try w.print("{s}", .{val});
                if (i < vals.len - 1) try w.writeAll(", ");
            }
            try w.writeAll(")");
        },
        .passthrough => |s| try w.writeAll(s),
        .raw_sql => |s| try w.writeAll(s),
    }
}
