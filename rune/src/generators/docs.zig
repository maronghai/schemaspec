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
                fk.fields[0],
                fk.ref_table,
                fk.ref_fields[0],
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
        try w.print("    {{ \"name\": \"{s}\"", .{table.name});
        if (table.doc) |doc| {
            try w.print(", \"doc\": \"{s}\"", .{doc});
        } else if (table.comment) |c| {
            try w.print(", \"description\": \"{s}\"", .{c});
        }
        try w.writeAll(", \"columns\": [");
        for (table.columns, 0..) |col, ci| {
            if (ci > 0) try w.writeAll(", ");
            try w.print("{{ \"name\": \"{s}\"", .{col.name});
            if (col.doc) |doc| {
                try w.print(", \"doc\": \"{s}\"", .{doc});
            } else if (col.comment) |c| {
                try w.print(", \"description\": \"{s}\"", .{c});
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
            try w.writeAll(c);
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

fn writeType(w: *Writer, col: typed_ast.TypedColumn) !void {
    switch (col.sql_type) {
        .int => try w.writeAll("INT"),
        .bigint => try w.writeAll("BIGINT"),
        .smallint => try w.writeAll("SMALLINT"),
        .decimal => |ds| try w.print("DECIMAL({d},{d})", .{ ds.precision, ds.scale }),
        .varchar => |n| {
            if (n > 0) {
                try w.print("VARCHAR({d})", .{n});
            } else {
                try w.writeAll("TEXT");
            }
        },
        .text => try w.writeAll("TEXT"),
        .blob => try w.writeAll("BLOB"),
        .json => try w.writeAll("JSON"),
        .jsonb => try w.writeAll("JSONB"),
        .datetime => try w.writeAll("DATETIME"),
        .date => try w.writeAll("DATE"),
        .timestamptz => try w.writeAll("TIMESTAMPTZ"),
        .boolean => try w.writeAll("BOOLEAN"),
        .uuid => try w.writeAll("UUID"),
        .inet => try w.writeAll("INET"),
        .serial => try w.writeAll("SERIAL"),
        .enum_values => |vals| {
            try w.writeAll("ENUM(");
            for (vals, 0..) |v, vi| {
                if (vi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{v});
            }
            try w.writeAll(")");
        },
        .raw_sql => |s| try w.writeAll(s),
        .passthrough => |s| try w.writeAll(s),
    }
}
