const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const utils = @import("../utils.zig");
const common = @import("common.zig");
const Writer = std.Io.Writer;
const Dialect = @import("../dialect/enum.zig").Dialect;

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

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");
    try w.writeAll("  \"$schema\": \"http://json-schema.org/draft-07/schema#\",\n");

    // Title from schema name
    if (typed.schema_name) |name| {
        try w.writeAll("  \"title\": \"");
        try utils.jsonEscapeString(w, name);
        try w.writeAll("\",\n");
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
    try common.writeTableSchemaJson(alloc, w, table, "    ", "#/$defs/");
}
