const std = @import("std");
const resolved_ast = @import("types/resolved_ast.zig");
const ast_mod = @import("types/ast.zig");
const utils = @import("utils.zig");

// ─── Documentation Generator ──────────────────────────────────
// Generates Markdown documentation from ResolvedAst.
// Output: structured Markdown with tables, fields, FKs, and templates.

pub fn generate(alloc: std.mem.Allocator, resolved: resolved_ast.ResolvedAst) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Title
    if (resolved.schema_name) |name| {
        try w.print("# {s} Schema Documentation\n\n", .{name});
    } else {
        try w.writeAll("# Schema Documentation\n\n");
    }

    // Schema info
    try w.writeAll("## Overview\n\n");
    try w.print("- **Tables:** {d}\n", .{resolved.tables.len});
    var total_fields: usize = 0;
    for (resolved.tables) |table| {
        total_fields += table.fields.len;
    }
    try w.print("- **Total Fields:** {d}\n", .{total_fields});
    try w.print("- **Views:** {d}\n\n", .{resolved.views.len});

    // Tables
    if (resolved.tables.len > 0) {
        try w.writeAll("## Tables\n\n");
        for (resolved.tables) |table| {
            try writeTable(alloc, w, table);
        }
    }

    // Views
    if (resolved.views.len > 0) {
        try w.writeAll("## Views\n\n");
        for (resolved.views) |view| {
            try w.print("### `{s}`\n\n", .{view.name});
            if (view.query.len > 0) {
                try w.print("```sql\n{s}\n```\n\n", .{view.query});
            }
        }
    }

    // FK Relationships
    var has_fks = false;
    for (resolved.tables) |table| {
        if (table.fks.len > 0) {
            has_fks = true;
            break;
        }
    }
    if (has_fks) {
        try w.writeAll("## Foreign Key Relationships\n\n");
        try w.writeAll("```\n");
        for (resolved.tables) |table| {
            for (table.fks) |fk| {
                try w.print("  {s}(", .{table.name});
                for (fk.fields, 0..) |field, fi| {
                    if (fi > 0) try w.writeAll(", ");
                    try w.print("{s}", .{field});
                }
                try w.writeAll(") -> ");
                try w.print("{s}(", .{fk.ref_table});
                for (fk.ref_fields, 0..) |ref_field, ri| {
                    if (ri > 0) try w.writeAll(", ");
                    try w.print("{s}", .{ref_field});
                }
                try w.writeAll(")\n");
            }
        }
        try w.writeAll("```\n\n");
    }

    try w.flush();
    var out = aw.toArrayList();
    return try out.toOwnedSlice(alloc);
}

fn writeTable(_: std.mem.Allocator, w: anytype, table: resolved_ast.ResolvedTable) !void {
    try w.print("### `{s}`\n\n", .{table.name});

    if (table.comment) |c| {
        if (c.len > 0) {
            try w.print("{s}\n\n", .{c});
        }
    }

    // Field table
    try w.writeAll("| Field | Type | Modifiers | Default | Description |\n");
    try w.writeAll("|-------|------|-----------|---------|-------------|\n");

    for (table.fields) |field| {
        if (std.mem.eql(u8, field.name, "...")) continue;

        try w.print("| `{s}` | ", .{field.name});

        // Type
        switch (field.type_info) {
            .none => try w.writeAll("any"),
            .simple => |s| try w.print("`{s}`", .{s}),
            .int_explicit => |n| try w.print("int({d})", .{n}),
            .decimal_explicit => |ds| try w.print("decimal({d},{d})", .{ ds.precision, ds.scale }),
            .varchar_explicit => |n| {
                if (n == 0) {
                    try w.writeAll("text");
                } else {
                    try w.print("varchar({d})", .{n});
                }
            },
            .enum_type => |vals| {
                try w.writeAll("enum(");
                for (vals, 0..) |v, vi| {
                    if (vi > 0) try w.writeAll(", ");
                    try w.print("`{s}`", .{v});
                }
                try w.writeAll(")");
            },
            .raw_sql => |s| try w.print("`{s}`", .{s}),
        }

        try w.writeAll(" | ");

        // Modifiers
        var mod_count: usize = 0;
        for (field.modifiers) |mod| {
            if (mod_count > 0) try w.writeAll(" ");
            switch (mod.kind) {
                .auto_inc_pk => try w.writeAll("++"),
                .auto_inc => try w.writeAll("+"),
                .primary_key => try w.writeAll("!"),
                .not_null => try w.writeAll("*"),
                .unsigned => try w.writeAll("u"),
                .inline_unique => try w.writeAll("@u"),
                .inline_index => try w.writeAll("@"),
                .virtual => try w.writeAll("VIRTUAL"),
                .stored => try w.writeAll("STORED"),
            }
            mod_count += 1;
        }
        if (mod_count == 0) try w.writeAll("-");

        try w.writeAll(" | ");

        // Default
        if (field.default_val) |dv| {
            try w.print("`{s}`", .{dv.value});
        } else {
            try w.writeAll("-");
        }

        try w.writeAll(" | ");

        // Comment
        if (field.comment) |c| {
            try w.print("{s}", .{c});
        }

        try w.writeAll(" |\n");
    }

    // Indexes
    if (table.indexes.len > 0) {
        try w.writeAll("\n**Indexes:**\n\n");
        for (table.indexes) |idx| {
            try w.print("- `{s}` (", .{idx.name});
            switch (idx.kind) {
                .regular => try w.writeAll("INDEX"),
                .unique => try w.writeAll("UNIQUE"),
                .primary_key => try w.writeAll("PRIMARY KEY"),
                .fulltext => try w.writeAll("FULLTEXT"),
            }
            try w.writeAll("): ");
            for (idx.fields, 0..) |field, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("{s}", .{field});
                if (idx.descending[fi]) try w.writeAll(" DESC");
            }
            try w.writeAll("\n");
        }
    }

    try w.writeAll("\n");
}
