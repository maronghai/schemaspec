const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const Writer = std.Io.Writer;

// ─── Documentation Generator ─────────────────────────────────
// Generates Markdown or JSON documentation from TypedAst.
// Supports `+` doc directive for structured documentation.

pub const DocFormat = enum {
    markdown,
    json,
};

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    return generateWithFormat(alloc, typed, .markdown);
}

pub fn generateWithFormat(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, format: DocFormat) ![]const u8 {
    return switch (format) {
        .markdown => generateMarkdown(alloc, typed),
        .json => generateJson(alloc, typed),
    };
}

fn generateMarkdown(alloc: std.mem.Allocator, typed: typed_ast.TypedAst) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Title
    if (typed.schema_name) |name| {
        try w.print("# {s} Schema Documentation\n\n", .{name});
    } else {
        try w.writeAll("# Schema Documentation\n\n");
    }

    // Overview
    try w.writeAll("## Overview\n\n");
    try w.print("- **Tables:** {d}\n", .{typed.tables.len});
    var total_fields: usize = 0;
    var total_fks: usize = 0;
    var total_indexes: usize = 0;
    for (typed.tables) |table| {
        total_fields += table.columns.len;
        total_fks += table.fks.len;
        total_indexes += table.indexes.len;
    }
    try w.print("- **Total Fields:** {d}\n", .{total_fields});
    if (total_fks > 0) {
        try w.print("- **Foreign Keys:** {d}\n", .{total_fks});
    }
    if (total_indexes > 0) {
        try w.print("- **Indexes:** {d}\n", .{total_indexes});
    }
    try w.print("- **Views:** {d}\n\n", .{typed.views.len});

    // Table of Contents
    if (typed.tables.len > 0) {
        try w.writeAll("## Table of Contents\n\n");
        for (typed.tables) |table| {
            try w.print("- [`{s}`](#{s})\n", .{ table.name, table.name });
        }
        try w.writeAll("\n");
    }

    // Mermaid ER Diagram
    if (typed.tables.len > 0) {
        try w.writeAll("## Schema Diagram\n\n");
        try w.writeAll("```mermaid\nerDiagram\n");
        for (typed.tables) |table| {
            try w.writeAll("    ");
            try writeMermaidEntity(w, table.name);
            try w.writeAll(" {\n");
            for (table.columns) |col| {
                const type_str = try colTypeToMermaid(alloc, col);
                defer alloc.free(type_str);
                // Mark primary key and unique
                var suffix_buf: [16]u8 = undefined;
                var suffix_len: usize = 0;
                if (col.flags.primary_key) {
                    @memcpy(suffix_buf[suffix_len..][0..3], " PK");
                    suffix_len += 3;
                }
                if (col.flags.inline_unique) {
                    @memcpy(suffix_buf[suffix_len..][0..3], " UQ");
                    suffix_len += 3;
                }
                try w.print("        {s} {s}{s}\n", .{ type_str, col.name, suffix_buf[0..suffix_len] });
            }
            try w.writeAll("    }\n");
        }
        // FK relationships with cardinality
        for (typed.tables) |table| {
            for (table.fks) |fk| {
                if (fk.fields.len > 0 and fk.ref_fields.len > 0) {
                    // Determine cardinality: nullable FK = optional, non-nullable = mandatory
                    var is_nullable = false;
                    for (table.columns) |col| {
                        if (std.mem.eql(u8, col.name, fk.fields[0])) {
                            is_nullable = col.flags.nullable;
                            break;
                        }
                    }
                    // Mermaid cardinality: }|--|| = mandatory many-to-one, }|o--o| = optional many-to-one
                    const rel = if (is_nullable) "}|o--o|" else "}|--||";
                    try w.writeAll("    ");
                    try writeMermaidEntity(w, table.name);
                    try w.print(" {s} ", .{rel});
                    try writeMermaidEntity(w, fk.ref_table);
                    try w.writeAll(" : \"");
                    try writeMarkdownCell(w, fk.fields[0]);
                    try w.writeAll("\"\n");
                }
            }
        }
        try w.writeAll("```\n\n");
    }

    // Custom Types
    if (typed.custom_types.len > 0) {
        try w.writeAll("## Custom Types\n\n");
        for (typed.custom_types) |ct| {
            try w.print("### `{s}`\n\n", .{ct.name});
            if (ct.base == .enum_type) {
                const vals = ct.base.enum_type;
                if (vals.len > 0) {
                    try w.writeAll("**Values:**\n\n");
                    for (vals) |v| {
                        try w.print("- `{s}`\n", .{v});
                    }
                    try w.writeAll("\n");
                }
            }
        }
    }

    // Tables
    if (typed.tables.len > 0) {
        try w.writeAll("## Tables\n\n");
        for (typed.tables) |table| {
            try writeTable(w, table);
        }
    }

    // Views
    if (typed.views.len > 0) {
        try w.writeAll("## Views\n\n");
        for (typed.views) |view| {
            try w.print("### `{s}`\n\n", .{view.name});
            const desc = view.doc orelse view.comment;
            if (desc) |c| {
                if (c.len > 0) {
                    try w.print("{s}\n\n", .{c});
                }
            }
            if (view.query.len > 0) {
                try w.print("```sql\n{s}\n```\n\n", .{view.query});
            }
        }
    }

    // FK Relationships
    var has_fks = false;
    for (typed.tables) |table| {
        for (table.fks) |fk| {
            if (!has_fks) {
                try w.writeAll("## Foreign Key Relationships\n\n");
                try w.writeAll("| Table | Column | References | Actions |\n");
                try w.writeAll("|-------|--------|-----------|----------|\n");
                has_fks = true;
            }
            // Format actions
            var action_buf: [128]u8 = undefined;
            var action_len: usize = 0;
            for (fk.actions) |action| {
                if (action_len > 0) {
                    if (action_len < action_buf.len) action_buf[action_len] = ' ';
                    action_len += 1;
                }
                const trigger_str = switch (action.trigger) {
                    .on_delete => "ON DELETE",
                    .on_update => "ON UPDATE",
                };
                const action_str = switch (action.action) {
                    .cascade => "CASCADE",
                    .set_null => "SET NULL",
                    .set_default => "SET DEFAULT",
                    .restrict => "RESTRICT",
                    .no_action => "NO ACTION",
                };
                for (trigger_str) |c| {
                    if (action_len < action_buf.len) action_buf[action_len] = c;
                    action_len += 1;
                }
                if (action_len < action_buf.len) action_buf[action_len] = ' ';
                action_len += 1;
                for (action_str) |c| {
                    if (action_len < action_buf.len) action_buf[action_len] = c;
                    action_len += 1;
                }
            }
            try w.print("| `{s}` | `{s}` | `{s}.{s}` | {s} |\n", .{
                table.name,
                try joinFields(alloc, fk.fields),
                fk.ref_table,
                try joinFields(alloc, fk.ref_fields),
                action_buf[0..action_len],
            });
        }
    }
    if (has_fks) try w.writeAll("\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

fn generateJson(alloc: std.mem.Allocator, typed: typed_ast.TypedAst) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");

    // Schema metadata
    if (typed.schema_name) |name| {
        try w.print("  \"schema\": \"{s}\",\n", .{name});
    } else {
        try w.writeAll("  \"schema\": null,\n");
    }

    // Counts
    var total_fields: usize = 0;
    var total_fks: usize = 0;
    var total_indexes: usize = 0;
    for (typed.tables) |table| {
        total_fields += table.columns.len;
        total_fks += table.fks.len;
        total_indexes += table.indexes.len;
    }
    try w.print("  \"tables\": {d},\n", .{typed.tables.len});
    try w.print("  \"fields\": {d},\n", .{total_fields});
    try w.print("  \"foreign_keys\": {d},\n", .{total_fks});
    try w.print("  \"indexes\": {d},\n", .{total_indexes});
    try w.print("  \"views\": {d},\n", .{typed.views.len});

    // Custom types
    if (typed.custom_types.len > 0) {
        try w.writeAll("  \"custom_types\": [\n");
        for (typed.custom_types, 0..) |ct, i| {
            if (i > 0) try w.writeAll(",\n");
            try w.print("    {{ \"name\": \"{s}\"", .{ct.name});
            if (ct.base == .enum_type) {
                try w.writeAll(", \"values\": [");
                for (ct.base.enum_type, 0..) |v, vi| {
                    if (vi > 0) try w.writeAll(", ");
                    try w.print("\"{s}\"", .{v});
                }
                try w.writeAll("]");
            }
            try w.writeAll("}");
        }
        try w.writeAll("\n  ],\n");
    }

    // Tables
    try w.writeAll("  \"table_list\": [\n");
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll(",\n");
        try w.writeAll("    { \"name\": ");
        try writeJsonStr(alloc, w, table.name);
        if (table.doc) |doc| {
            try w.writeAll(", \"doc\": ");
            try writeJsonStr(alloc, w, doc);
        } else if (table.comment) |c| {
            try w.writeAll(", \"description\": ");
            try writeJsonStr(alloc, w, c);
        }
        try w.writeAll(", \"columns\": [");
        for (table.columns, 0..) |col, ci| {
            if (ci > 0) try w.writeAll(", ");
            try w.writeAll("{ \"name\": ");
            try writeJsonStr(alloc, w, col.name);
            if (col.doc) |doc| {
                try w.writeAll(", \"doc\": ");
                try writeJsonStr(alloc, w, doc);
            } else if (col.comment) |c| {
                try w.writeAll(", \"description\": ");
                try writeJsonStr(alloc, w, c);
            }
            try w.writeAll(" }");
        }
        try w.writeAll("] }");
    }
    try w.writeAll("\n  ]\n");

    try w.writeAll("}\n");
    try w.flush();
    return try aw.toOwnedSlice();
}

fn writeTable(w: *Writer, table: typed_ast.TypedTable) !void {
    try w.print("### `{s}`\n\n", .{table.name});
    const desc = table.doc orelse table.comment;
    if (desc) |c| {
        if (c.len > 0) {
            try w.print("{s}\n\n", .{c});
        }
    }

    // Columns table
    try w.writeAll("| Column | Type | Nullable | Default | Description |\n");
    try w.writeAll("|--------|------|----------|---------|-------------|\n");

    for (table.columns) |col| {
        try w.writeAll("| `");
        try w.writeAll(col.name);
        try w.writeAll("` | `");
        try writeType(w, col);
        try w.writeAll("` | ");
        try w.writeAll(if (col.flags.nullable) "yes" else "no");
        try w.writeAll(" | ");
        if (col.default) |dflt| {
            if (dflt.len > 0) {
                try w.writeAll("`");
                try w.writeAll(dflt);
                try w.writeAll("`");
            }
        }
        try w.writeAll(" | ");
        const col_desc = col.doc orelse col.comment;
        if (col_desc) |c| {
            try writeMarkdownCell(w, c);
        }
        try w.writeAll(" |\n");
    }

    // Indexes
    if (table.indexes.len > 0) {
        try w.writeAll("\n**Indexes:**\n\n");
        for (table.indexes) |idx| {
            try w.writeAll("- `");
            try w.writeAll(idx.name);
            try w.writeAll("` (");
            for (idx.fields, 0..) |field, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.writeAll(field);
            }
            try w.writeAll(")");
            if (idx.kind == .unique) {
                try w.writeAll(" — unique");
            }
            try w.writeAll("\n");
        }
    }

    // CHECK Constraints
    var has_checks = false;
    for (table.columns) |col| {
        if (col.check != null) {
            if (!has_checks) {
                try w.writeAll("\n**CHECK Constraints:**\n\n");
                has_checks = true;
            }
            try w.print("- `{s}`: `{s}`\n", .{ col.name, col.check.?.expr });
        }
    }

    try w.writeAll("\n");
}

/// Write `s` as a Markdown table cell: escape pipes (they would split the
/// cell) and drop backticks-unbalanced content hazards by escaping bare
/// backticks. Newlines become spaces (a row must stay one line).
fn writeMarkdownCell(w: *Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '|' => try w.writeAll("\\|"),
            '\n', '\r' => try w.writeByte(' '),
            else => try w.writeByte(c),
        }
    }
}

/// Write a Mermaid erDiagram entity name. Mermaid identifiers cannot contain
/// spaces or most punctuation; quoted form `["name"]` handles those.
fn writeMermaidEntity(w: *Writer, name: []const u8) !void {
    var safe = true;
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) {
            safe = false;
            break;
        }
    }
    if (safe and name.len > 0 and !std.ascii.isDigit(name[0])) {
        try w.writeAll(name);
    } else {
        try w.writeAll("[\"");
        try writeMarkdownCell(w, name);
        try w.writeAll("\"]");
    }
}

/// Convert a TypedColumn's SQL type to a Mermaid-friendly type string.
fn colTypeToMermaid(alloc: std.mem.Allocator, col: typed_ast.TypedColumn) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try writeType(w, col);
    try w.flush();
    return try aw.toOwnedSlice();
}

fn writeType(w: *Writer, col: typed_ast.TypedColumn) !void {
    const common = @import("common.zig");
    try common.writeSqlTypeString(w, col.sql_type, true);
}

/// Comma-join FK field names for docs tables — compound FKs were previously
/// truncated to their first column, hiding half the constraint.
fn joinFields(alloc: std.mem.Allocator, fields: []const []const u8) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 32);
    for (fields, 0..) |f, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, f);
    }
    return buf.items;
}

/// JSON string with escaping — table/column comments can contain quotes;
/// raw interpolation produced invalid JSON (v0.334.0).
fn writeJsonStr(alloc: std.mem.Allocator, w: *Writer, s: []const u8) !void {
    _ = alloc;
    const utils = @import("../utils.zig");
    try w.writeAll("\"");
    try utils.jsonEscapeString(w, s);
    try w.writeAll("\"");
}
