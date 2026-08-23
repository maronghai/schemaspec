const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const Writer = std.Io.Writer;
const common = @import("common.zig");

// ─── Prisma Schema Generator ─────────────────────────────────
// Maps Rune .ss schema to Prisma schema language.
// Output: Prisma model definitions with fields, relations, and attributes.
//
// Architecture: TypedAst → Prisma schema string
//   Each table → model block
//   Each column → field with Prisma type
//   FK → relation field with @relation
//   Primary key → @id
//   Auto-increment → @default(autoincrement())
//   Unique → @unique
//   Optional → ? suffix
//   Enum values → enum block

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Generate enum blocks first
    const has_enums = common.hasAnyEnums(typed);
    if (has_enums) {
        for (typed.tables) |table| {
            for (table.columns) |col| {
                if (col.flags.is_enum) {
                    try w.print("enum {s}Type {{\n", .{col.name});
                    for (col.enum_values) |val| {
                        try w.print("  {s}\n", .{val});
                    }
                    try w.writeAll("}\n\n");
                }
            }
        }
    }

    // Generate model blocks
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try w.print("model {s} {{\n", .{table.name});

        // Columns
        for (table.columns) |col| {
            try writeField(w, col);
        }

        // Inline relations from FK targets (owned side)
        for (table.fks) |fk| {
            // Compound FKs list every column — Prisma requires fields and
            // references counts to match the constraint exactly.
            try w.writeAll("  ");
            try w.writeAll(try common.toCamelSingular(alloc, fk.ref_table));
            try w.print(" {s}? @relation(\"{s}_{s}\", fields: [", .{ fk.ref_table, table.name, fk.ref_table });
            for (fk.fields, 0..) |f, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll(f);
            }
            try w.writeAll("], references: [");
            for (fk.ref_fields, 0..) |f, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll(f);
            }
            try w.writeAll("])\n");
        }

        // Relation blocks for the other side
        try w.writeAll("\n  @@map(\"");
        try w.writeAll(table.name);
        try w.writeAll("\")\n");

        try w.writeAll("}\n");
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

fn writeField(w: *Writer, col: typed_ast.TypedColumn) !void {
    const prisma_type = mapType(col);
    // Primary keys are never nullable in Prisma
    const optional_suffix = if (col.flags.nullable and !col.flags.primary_key) "?" else "";

    try w.print("  {s} {s}{s}", .{ col.name, prisma_type, optional_suffix });

    // Precision annotation — a bare Decimal loses precision/scale and the
    // Prisma-migrated column degrades to the database default.
    if (col.sql_type == .decimal) {
        const ds = col.sql_type.decimal;
        try w.print(" @db.Decimal({d}, {d})", .{ ds.precision, ds.scale });
    }

    // Attributes — write directly to main writer
    if (col.flags.primary_key) {
        try w.writeAll(" @id");
        if (col.flags.auto_increment) {
            try w.writeAll(" @default(autoincrement())");
        }
    } else if (col.flags.auto_increment) {
        try w.writeAll(" @default(autoincrement())");
    }

    if (col.flags.inline_unique and !col.flags.primary_key) {
        try w.writeAll(" @unique");
    }

    if (col.flags.is_enum) {
        if (col.enum_values.len > 0) {
            try w.print(" @default({s})", .{col.enum_values[0]});
        }
    } else if (col.default) |dflt| {
        if (common.shouldEmitDefault(dflt)) {
            try w.print(" @default({s})", .{dflt});
        }
    }

    try w.writeAll("\n");
}

fn mapType(col: typed_ast.TypedColumn) []const u8 {
    if (col.flags.is_enum) return "String";
    return switch (col.sql_type) {
        .int, .smallint => "Int",
        .bigint, .serial => "BigInt",
        .decimal => "Decimal",
        .varchar, .text => "String",
        .blob => "Bytes",
        .json, .jsonb => "Json",
        .datetime, .timestamptz, .date => "DateTime",
        .boolean => "Boolean",
        .uuid => "String",
        .inet => "String",
        .enum_values => "String",
        .raw_sql, .passthrough => "String",
    };
}
