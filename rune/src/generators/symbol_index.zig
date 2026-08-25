const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const utils = @import("../utils.zig");
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
        try writeJsonStr(w, name);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\n  \"tables\": [\n");

    for (ast.tables, 0..) |table, table_idx| {
        try w.writeAll("    {\n      \"name\": ");
        try writeJsonStr(w, table.name);
        try w.print(",\n      \"line\": {d},\n", .{table.line_no});

        if (table.comment) |comment| {
            try w.writeAll("      \"comment\": ");
            try writeJsonStr(w, comment);
            try w.writeAll(",\n");
        }

        try w.writeAll("      \"columns\": [\n");
        for (table.columns, 0..) |col, col_idx| {
            try w.writeAll("        { \"name\": ");
            try writeJsonStr(w, col.name);
            // Type strings can contain quotes (enum values); escape the whole
            // rendered type rather than trusting writeSqlType's raw output.
            var type_buf = std.Io.Writer.Allocating.init(alloc);
            defer type_buf.deinit();
            try writeSqlType(&type_buf.writer, col.sql_type);
            try w.writeAll(", \"type\": ");
            try writeJsonStr(w, type_buf.written());
            try w.writeAll("");
            if (col.comment) |comment| {
                try w.writeAll(", \"comment\": ");
                try writeJsonStr(w, comment);
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
                    try writeJsonStr(w, field);
                    if (field_idx < fk.fields.len - 1) try w.writeAll(", ");
                }
                try w.writeAll("], \"references\": { \"table\": ");
                try writeJsonStr(w, fk.ref_table);
                try w.writeAll(", \"fields\": [");
                for (fk.ref_fields, 0..) |ref_field, ref_idx| {
                    try writeJsonStr(w, ref_field);
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
                try w.writeAll("        { \"name\": ");
                try writeJsonStr(w, idx.name);
                try w.writeAll(", \"fields\": [");
                for (idx.fields, 0..) |field, field_idx| {
                    try writeJsonStr(w, field);
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

/// Write a JSON string literal with proper escaping — comments and names can
/// contain quotes; raw interpolation produced output that failed JSON.parse.
fn writeJsonStr(w: anytype, s: []const u8) !void {
    try w.writeAll("\"");
    try utils.jsonEscapeString(w, s);
    try w.writeAll("\"");
}

fn writeSqlType(w: anytype, sql_type: sql_type_mod.SqlType) !void {
    // Delegate to the shared helper in common.zig.
    // We wrap the writer to satisfy the *std.Io.Writer type.
    const common = @import("common.zig");
    // Symbol index uses lowercase SQL type names.
    try common.writeSqlTypeString(w, sql_type, false);
}
