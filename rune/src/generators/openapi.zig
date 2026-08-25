const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const utils = @import("../utils.zig");
const common = @import("common.zig");
const version = @import("../version.zig");
const Writer = std.Io.Writer;
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── OpenAPI 3.1 Generator ────────────────────────────────────
// Produces an OpenAPI 3.1 specification from TypedAst.
// Output: components/schemas with table objects, optional paths stubs.
//
// Architecture: TypedAst → OpenAPI 3.1 JSON
//   info: from schema name + VERSION
//   components/schemas: each table → object schema with properties, required, description
//   Each column → property with type from SqlType.toJsonSchema()
//   Non-nullable → required array
//   Comment → description
//   Enum values → enum array
//   FK columns → $ref to referenced table's schema

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");
    try w.writeAll("  \"openapi\": \"3.1.0\",\n");

    // Info block
    try w.writeAll("  \"info\": {\n");
    if (typed.schema_name) |name| {
        try w.writeAll("    \"title\": \"");
        try utils.jsonEscapeString(w, name);
        try w.writeAll("\",\n");
    } else {
        try w.writeAll("    \"title\": \"rune-schema\",\n");
    }
    try w.writeAll("    \"version\": \"");
    try utils.jsonEscapeString(w, version.VERSION);
    try w.writeAll("\"\n");
    try w.writeAll("  },\n");

    // Paths — empty (schema-only, no endpoints)
    try w.writeAll("  \"paths\": {},\n");

    // Components
    try w.writeAll("  \"components\": {\n");
    try w.writeAll("    \"schemas\": {\n");

    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll(",\n");
        try writeTableSchema(alloc, w, table);
    }

    // Views as read-only schemas
    for (typed.views, 0..) |view, vi| {
        if (typed.tables.len > 0 or vi > 0) try w.writeAll(",\n");
        try writeViewSchema(w, view);
    }

    if (typed.tables.len == 0 and typed.views.len == 0) try w.writeAll("\n");
    try w.writeAll("    }\n");
    try w.writeAll("  }\n");

    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Table Schema ─────────────────────────────────────────────

fn writeTableSchema(alloc: std.mem.Allocator, w: *Writer, table: typed_ast.TypedTable) !void {
    try common.writeTableSchemaJson(alloc, w, table, "      ", "#/components/schemas/");
}

// ─── View Schema (read-only) ─────────────────────────────────

fn writeViewSchema(w: *Writer, view: typed_ast.TypedView) !void {
    try w.writeAll("      \"");
    try utils.jsonEscapeString(w, view.name);
    try w.writeAll("\": {\n");
    try w.writeAll("        \"type\": \"object\",\n");

    if (view.comment) |c| {
        if (c.len > 0) {
            try w.writeAll("        \"description\": \"");
            try utils.jsonEscapeString(w, c);
            try w.writeAll("\",\n");
        }
    }

    try w.writeAll("        \"readOnly\": true\n");
    try w.writeAll("      }");
}
