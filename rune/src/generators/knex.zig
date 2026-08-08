const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const Writer = std.Io.Writer;
const common = @import("common.zig");

// ─── Knex Migration Generator ───────────────────────────────────
// Maps Rune .ss schema to Knex.js migration files (JavaScript).
// Output: JavaScript with exports.up / exports.down functions.
//
// Architecture: TypedAst → JavaScript string
//   Each table → createTable() in exports.up, dropTableIfExists() in exports.down
//   Each column → table.<type>() with modifiers
//   FK → table.foreign().references()
//   Index → table.index()

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Generate exports.up
    try w.writeAll("/**\n");
    try w.writeAll(" * @param {import('knex').Knex} knex\n");
    try w.writeAll(" * @returns {Promise<void>}\n");
    try w.writeAll(" */\n");
    try w.writeAll("exports.up = function(knex) {\n");

    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try writeUpTable(w, table);
    }

    try w.writeAll("};\n\n");

    // Generate exports.down
    try w.writeAll("/**\n");
    try w.writeAll(" * @param {import('knex').Knex} knex\n");
    try w.writeAll(" * @returns {Promise<void>}\n");
    try w.writeAll(" */\n");
    try w.writeAll("exports.down = function(knex) {\n");

    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try writeDownTable(w, table);
    }

    try w.writeAll("};\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Up (createTable) Generation ────────────────────────────────

fn writeUpTable(w: *Writer, table: typed_ast.TypedTable) !void {
    // Comment
    if (table.comment) |comment| {
        if (comment.len > 0) {
            try w.print("  // {s}\n", .{comment});
        }
    }

    try w.print("  return knex.schema.createTable('{s}', function(table) {{\n", .{table.name});

    // Columns
    for (table.columns) |col| {
        try writeColumn(w, col, table);
    }

    // Single-column foreign keys
    for (table.fks) |fk| {
        if (fk.fields.len == 1) {
            try w.print("    table.foreign('{s}').references('{s}.{s}');\n", .{
                fk.fields[0],
                fk.ref_table,
                fk.ref_fields[0],
            });
        } else {
            // Composite FK
            try w.print("    table.foreign([", .{});
            for (fk.fields, 0..) |field, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{field});
            }
            try w.writeAll("]).references([");
            for (fk.ref_fields, 0..) |field, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{field});
            }
            try w.print("]).inTable('{s}');\n", .{fk.ref_table});
        }
    }

    // Indexes (single-column)
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) continue;
        if (idx.fields.len == 1) {
            if (idx.kind == .unique) {
                try w.print("    table.unique('{s}', {{ indexName: '{s}' }});\n", .{ idx.fields[0], idx.name });
            } else {
                try w.print("    table.index('{s}', '{s}');\n", .{ idx.fields[0], idx.name });
            }
        } else {
            // Composite index
            if (idx.kind == .unique) {
                try w.print("    table.unique([", .{});
                for (idx.fields, 0..) |field, fi| {
                    if (fi > 0) try w.writeAll(", ");
                    try w.print("'{s}'", .{field});
                }
                try w.print("], {{ indexName: '{s}' }});\n", .{idx.name});
            } else {
                try w.print("    table.index([", .{});
                for (idx.fields, 0..) |field, fi| {
                    if (fi > 0) try w.writeAll(", ");
                    try w.print("'{s}'", .{field});
                }
                try w.print("], '{s}');\n", .{idx.name});
            }
        }
    }

    try w.writeAll("  });\n");
}

// ─── Down (dropTableIfExists) Generation ────────────────────────

fn writeDownTable(w: *Writer, table: typed_ast.TypedTable) !void {
    try w.print("  return knex.schema.dropTableIfExists('{s}');\n", .{table.name});
}

// ─── Column Generation ──────────────────────────────────────────

fn writeColumn(w: *Writer, col: typed_ast.TypedColumn, table: typed_ast.TypedTable) !void {
    // Comment
    if (col.comment) |comment| {
        if (comment.len > 0) {
            try w.print("    // {s}\n", .{comment});
        }
    }

    // Check if this column is an FK — if so, skip it (handled by .foreign())
    for (table.fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col.name)) {
            return; // FK column handled by .foreign()
        }
    }

    // Primary key with autoincrement
    if (col.flags.primary_key and col.flags.auto_increment) {
        try w.print("    table.increments('{s}').primary();\n", .{col.name});
        return;
    }

    // Primary key without autoincrement
    if (col.flags.primary_key) {
        try w.print("    table.{s}('{s}').primary()", .{ knexType(col), col.name });
        try writeColumnOptions(w, col);
        try w.writeAll(";\n");
        return;
    }

    // Regular column
    switch (col.sql_type) {
        .varchar => |len| if (len > 0)
            try w.print("    table.{s}('{s}', {d})", .{ knexType(col), col.name, len })
        else
            try w.print("    table.{s}('{s}')", .{ knexType(col), col.name }),
        else => try w.print("    table.{s}('{s}')", .{ knexType(col), col.name }),
    }

    // Modifiers
    if (!col.flags.nullable) {
        try w.writeAll(".notNullable()");
    }
    if (col.flags.inline_unique) {
        try w.writeAll(".unique()");
    }
    if (col.flags.inline_index) {
        try w.writeAll(".index()");
    }

    // Default value
    if (col.default) |dflt| {
        if (common.shouldEmitDefault(dflt)) {
            try w.writeAll(".defaultTo(");
            try common.writeFormattedDefault(w, dflt, common.getOrmFormatter(.knex));
            try w.writeAll(")");
        }
    }

    try w.writeAll(";\n");
}

fn knexType(col: typed_ast.TypedColumn) []const u8 {
    if (col.flags.is_enum) {
        return "enu"; // Knex enum
    }
    return switch (col.sql_type) {
        .int, .serial => "integer",
        .smallint => "smallint",
        .bigint => "bigInteger",
        .decimal => "decimal",
        .varchar => "string",
        .text => "text",
        .blob => "binary",
        .json, .jsonb => "json",
        .datetime, .timestamptz => "timestamp",
        .date => "date",
        .boolean => "boolean",
        .uuid => "uuid",
        .inet => "string",
        .enum_values => "enu",
        .raw_sql, .passthrough => "string",
    };
}

fn writeColumnOptions(w: *Writer, col: typed_ast.TypedColumn) !void {
    if (!col.flags.nullable) {
        try w.writeAll(".notNullable()");
    }
    if (col.default) |dflt| {
        if (common.shouldEmitDefault(dflt)) {
            try w.writeAll(".defaultTo(");
            try common.writeFormattedDefault(w, dflt, common.getOrmFormatter(.knex));
            try w.writeAll(")");
        }
    }
}
