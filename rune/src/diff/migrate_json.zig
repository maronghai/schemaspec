const std = @import("std");
const diff_mod = @import("../diff/engine.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const utils = @import("../utils.zig");
const dialect_enum = @import("../dialect/enum.zig");

const Dialect = dialect_enum.Dialect;

// ─── generateMigrationJson: structured migration JSON ─────────

pub fn generateMigrationJson(
    alloc: std.mem.Allocator,
    d: diff_mod.SchemaDiff,
    dialect: Dialect,
) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n  \"operations\":");

    var op_count: usize = 0;

    // Count operations for comma handling
    op_count += d.dropped_tables.len;
    for (d.table_diffs) |td| {
        if (td.action == .create) op_count += 1;
        op_count += td.field_diffs.len;
        op_count += td.index_diffs.len;
        op_count += td.fk_diffs.len;
        if (td.metadata_diff) |md| {
            if (md.hasChanges()) op_count += 1;
        }
    }
    op_count += d.view_diffs.len;

    if (op_count == 0) {
        try w.writeAll(" []");
    } else {
        try w.writeAll(" [\n");
        var emitted: usize = 0;

        // Drop tables
        for (d.dropped_tables) |tname| {
            if (emitted > 0) try w.writeAll(",\n");
            try w.writeAll("    {\"type\": \"drop_table\", \"table\": \"");
            try utils.jsonEscapeString(w, tname);
            try w.writeAll("\"}");
            emitted += 1;
        }

        // Table diffs
        for (d.table_diffs) |td| {
            if (td.action == .create) {
                if (emitted > 0) try w.writeAll(",\n");
                try w.writeAll("    {\"type\": \"create_table\", \"table\": \"");
                try utils.jsonEscapeString(w, td.name);
                try w.writeAll("\"}");
                emitted += 1;
            }

            // Field diffs
            for (td.field_diffs) |fd| {
                if (emitted > 0) try w.writeAll(",\n");
                switch (fd.action) {
                    .add => {
                        try w.writeAll("    {\"type\": \"add_column\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"column\": \"");
                        try utils.jsonEscapeString(w, fd.name);
                        try w.writeAll("\"}");
                    },
                    .drop => {
                        try w.writeAll("    {\"type\": \"drop_column\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"column\": \"");
                        try utils.jsonEscapeString(w, fd.name);
                        try w.writeAll("\"}");
                    },
                    .modify => {
                        try w.writeAll("    {\"type\": \"modify_column\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"column\": \"");
                        try utils.jsonEscapeString(w, fd.name);
                        try w.writeAll("\"}");
                    },
                    .rename => {
                        try w.writeAll("    {\"type\": \"rename_column\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"from\": \"");
                        if (fd.rename_from) |rf| try utils.jsonEscapeString(w, rf);
                        try w.writeAll("\", \"to\": \"");
                        try utils.jsonEscapeString(w, fd.name);
                        try w.writeAll("\"}");
                    },
                }
                emitted += 1;
            }

            // Index diffs
            for (td.index_diffs) |idx_diff| {
                if (emitted > 0) try w.writeAll(",\n");
                switch (idx_diff.action) {
                    .add => {
                        try w.writeAll("    {\"type\": \"add_index\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"index\": \"");
                        try utils.jsonEscapeString(w, idx_diff.name);
                        try w.writeAll("\"}");
                    },
                    .drop => {
                        try w.writeAll("    {\"type\": \"drop_index\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"index\": \"");
                        try utils.jsonEscapeString(w, idx_diff.name);
                        try w.writeAll("\"}");
                    },
                    .modify => {
                        try w.writeAll("    {\"type\": \"modify_index\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\", \"index\": \"");
                        try utils.jsonEscapeString(w, idx_diff.name);
                        try w.writeAll("\"}");
                    },
                }
                emitted += 1;
            }

            // FK diffs
            for (td.fk_diffs) |fk_diff| {
                if (emitted > 0) try w.writeAll(",\n");
                switch (fk_diff.action) {
                    .add => {
                        try w.writeAll("    {\"type\": \"add_fk\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\"}");
                    },
                    .drop => {
                        try w.writeAll("    {\"type\": \"drop_fk\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\"}");
                    },
                    .modify => {
                        try w.writeAll("    {\"type\": \"modify_fk\", \"table\": \"");
                        try utils.jsonEscapeString(w, td.name);
                        try w.writeAll("\"}");
                    },
                }
                emitted += 1;
            }

            // Metadata diffs
            if (td.metadata_diff) |md| {
                if (md.hasChanges()) {
                    if (emitted > 0) try w.writeAll(",\n");
                    try w.writeAll("    {\"type\": \"alter_metadata\", \"table\": \"");
                    try utils.jsonEscapeString(w, td.name);
                    try w.writeAll("\"}");
                    emitted += 1;
                }
            }
        }

        // View diffs
        for (d.view_diffs) |vd| {
            if (emitted > 0) try w.writeAll(",\n");
            switch (vd.action) {
                .create => {
                    try w.writeAll("    {\"type\": \"create_view\", \"view\": \"");
                    try utils.jsonEscapeString(w, vd.name);
                    try w.writeAll("\"}");
                },
                .drop => {
                    try w.writeAll("    {\"type\": \"drop_view\", \"view\": \"");
                    try utils.jsonEscapeString(w, vd.name);
                    try w.writeAll("\"}");
                },
                .modify => {
                    try w.writeAll("    {\"type\": \"modify_view\", \"view\": \"");
                    try utils.jsonEscapeString(w, vd.name);
                    try w.writeAll("\"}");
                },
            }
            emitted += 1;
        }

        try w.writeAll("\n  ]");
    }

    try w.print(",\n  \"dialect\": \"{s}\"", .{@tagName(dialect)});
    try w.print(",\n  \"wrapped_in_transaction\": true", .{});
    try w.writeAll("\n}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}
