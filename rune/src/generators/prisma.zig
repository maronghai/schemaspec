const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
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

    // Generate enum blocks first. Same column name in multiple tables would
    // declare the same enum type twice (invalid Prisma). Identical value
    // sets share one declaration; differing sets get a table-qualified name.
    const has_enums = common.hasAnyEnums(typed);
    if (has_enums) {
        var seen = std.StringHashMap([]const u8).init(alloc); // col name -> values signature
        defer seen.deinit();
        for (typed.tables) |table| {
            for (table.columns) |col| {
                if (!(col.flags.is_enum and col.enum_values.len > 0)) continue;
                const sig = try joinEnumValues(alloc, col.enum_values);
                if (seen.get(col.name)) |existing_sig| {
                    if (std.mem.eql(u8, existing_sig, sig)) continue; // identical — emit once
                    try w.print("enum {s}_{s}Type {{\n", .{ col.name, table.name });
                    for (col.enum_values) |val| {
                        try w.print("  {s}\n", .{val});
                    }
                    try w.writeAll("}\n\n");
                } else {
                    try seen.put(try alloc.dupe(u8, col.name), sig);
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
            try w.writeAll("]");
            if (fk.actions.len > 0) {
                try w.writeAll(", ");
                try writePrismaActions(w, fk.actions);
            }
            try w.writeAll(")\n");
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
    if (col.flags.unsigned and (col.sql_type == .int or col.sql_type == .bigint)) {
        try w.writeAll(" @db.UnsignedInt");
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
        // User's explicit default wins; only fall back to the first enum
        // value when no default was declared. The old code always used the
        // first value, silently overriding `=live` with `=draft`.
        if (col.default) |dflt| {
            try writePrismaDefault(w, col, dflt);
        } else if (col.enum_values.len > 0) {
            try w.print(" @default({s})", .{col.enum_values[0]});
        }
    } else if (col.default) |dflt| {
        if (common.shouldEmitDefault(dflt)) {
            try writePrismaDefault(w, col, dflt);
        }
    }

    // datetime `+` means DEFAULT CURRENT_TIMESTAMP.
    if (col.default == null and col.flags.has_timestamp_default and col.flags.is_datetime) {
        try w.writeAll(" @default(now())");
    }

    try w.writeAll("\n");
}

/// Prisma default value: strings must be double-quoted (a bare word parses
/// as an enum/identifier reference); numerics and booleans pass through.
fn writePrismaDefault(w: *Writer, col: typed_ast.TypedColumn, dflt: []const u8) !void {
    _ = col;
    var trimmed = std.mem.trim(u8, dflt, " ");
    if (trimmed.len >= 2 and (trimmed[0] == '\'' or trimmed[0] == '"') and trimmed[trimmed.len - 1] == trimmed[0]) {
        const inner = trimmed[1 .. trimmed.len - 1];
        try w.print(" @default(\"{s}\")", .{inner});
        return;
    }
    // Numeric literal → pass through unquoted.
    var all_numeric = trimmed.len > 0;
    for (trimmed) |c| {
        if (!std.ascii.isDigit(c) and c != '.' and c != '-') {
            all_numeric = false;
            break;
        }
    }
    if (all_numeric) {
        try w.print(" @default({s})", .{trimmed});
        return;
    }
    // Anything else is a word — Prisma would parse it as an identifier
    // reference, not a string. Quote it.
    try w.print(" @default(\"{s}\")", .{trimmed});
}

fn joinEnumValues(alloc: std.mem.Allocator, values: []const []const u8) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 32);
    for (values, 0..) |v, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, v);
    }
    return buf.items;
}

/// Prisma referential action list: onDelete first (if present), then onUpdate.
fn writePrismaActions(w: *Writer, actions: []const ast_mod.FkAction) !void {
    var wrote_any = false;
    for (actions) |a| {
        if (a.trigger != .on_delete) continue;
        try w.print("onDelete: {s}", .{prismaActionName(a.action)});
        wrote_any = true;
    }
    for (actions) |a| {
        if (a.trigger != .on_update) continue;
        if (wrote_any) try w.writeAll(", ");
        try w.print("onUpdate: {s}", .{prismaActionName(a.action)});
        wrote_any = true;
    }
}

fn prismaActionName(action: ast_mod.FkActionType) []const u8 {
    return switch (action) {
        .cascade => "Cascade",
        .set_null => "SetNull",
        .set_default => "SetDefault",
        .restrict => "Restrict",
        .no_action => "NoAction",
    };
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
