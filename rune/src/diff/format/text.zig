const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const dialect_mod = @import("../../dialect/dialect.zig");
const utils = @import("../../utils.zig");
const format_common = @import("../../diff/format_common.zig");
const cli = @import("../../cli.zig");
const color_mod = @import("../../color.zig");
const SchemaDiff = diff_types.SchemaDiff;
const Dialect = @import("../../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

const formatTypeInfo = format_common.formatTypeInfo;

/// Count diff statistics for summary output.
const DiffStats = struct {
    dropped_tables: usize = 0,
    added_tables: usize = 0,
    modified_tables: usize = 0,
    added_fields: usize = 0,
    dropped_fields: usize = 0,

    fn compute(d: SchemaDiff) DiffStats {
        var stats = DiffStats{};
        stats.dropped_tables = d.dropped_tables.len;
        for (d.table_diffs) |td| {
            switch (td.action) {
                .create => stats.added_tables += 1,
                .alter => {
                    var has_changes = false;
                    for (td.field_diffs) |fd| {
                        switch (fd.action) {
                            .add => { stats.added_fields += 1; has_changes = true; },
                            .drop => { stats.dropped_fields += 1; has_changes = true; },
                            .modify, .rename => has_changes = true,
                        }
                    }
                    if (td.index_diffs.len > 0 or td.fk_diffs.len > 0 or td.metadata_diff != null) has_changes = true;
                    if (has_changes) stats.modified_tables += 1;
                },
            }
        }
        return stats;
    }
};

/// Core diff formatting logic — writes to any std.io.Writer with optional ANSI color support.
pub fn writeDiffTo(w: anytype, d: SchemaDiff, q: u8, use_color: bool) !void {
    for (d.dropped_tables) |tname| {
        if (use_color) {
            try w.writeAll(color_mod.RED);
            try w.print("-- DROP TABLE {c}{s}{c}\n", .{ q, tname, q });
            try w.writeAll(color_mod.RESET);
        } else {
            try w.print("-- DROP TABLE {c}{s}{c}\n", .{ q, tname, q });
        }
    }

    for (d.view_diffs) |vd| {
        switch (vd.action) {
            .create => {
                if (use_color) {
                    try w.writeAll(color_mod.GREEN);
                    try w.print("-- CREATE VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- CREATE VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                }
            },
            .drop => {
                if (use_color) {
                    try w.writeAll(color_mod.RED);
                    try w.print("-- DROP VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- DROP VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                }
            },
            .modify => {
                if (use_color) {
                    try w.writeAll(color_mod.YELLOW);
                    try w.print("-- ALTER VIEW {c}{s}{c} (query changed)\n", .{ q, vd.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- ALTER VIEW {c}{s}{c} (query changed)\n", .{ q, vd.name, q });
                }
            },
        }
    }

    for (d.table_diffs) |td| {
        if (td.action == .create) {
            if (use_color) {
                try w.writeAll(color_mod.GREEN);
                try w.print("-- CREATE TABLE {c}{s}{c}\n", .{ q, td.name, q });
                try w.writeAll(color_mod.RESET);
            } else {
                try w.print("-- CREATE TABLE {c}{s}{c}\n", .{ q, td.name, q });
            }
            for (td.field_diffs) |fd| {
                if (use_color) {
                    try w.writeAll(color_mod.GREEN);
                    try w.print("  + {s}\n", .{fd.name});
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("  + {s}\n", .{fd.name});
                }
            }
            for (td.index_diffs) |idx| {
                if (use_color) {
                    try w.writeAll(color_mod.GREEN);
                    try w.print("  + @{s}\n", .{idx.name});
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("  + @{s}\n", .{idx.name});
                }
            }
            for (td.fk_diffs) |fk| {
                if (fk.new_fk) |nfk| {
                    if (use_color) {
                        try w.writeAll(color_mod.GREEN);
                        try w.print("  + FK → {s}\n", .{nfk.ref_table});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  + FK → {s}\n", .{nfk.ref_table});
                    }
                }
            }
            continue;
        }

        // alter
        var table_has_changes = false;
        for (td.field_diffs) |fd| {
            if (!table_has_changes) {
                if (use_color) {
                    try w.writeAll(color_mod.BLUE ++ color_mod.BOLD);
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                }
                table_has_changes = true;
            }
            switch (fd.action) {
                .add => {
                    if (use_color) {
                        try w.writeAll(color_mod.GREEN);
                        try w.print("  + {s} (add)\n", .{fd.name});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  + {s} (add)\n", .{fd.name});
                    }
                },
                .drop => {
                    if (use_color) {
                        try w.writeAll(color_mod.RED);
                        try w.print("  - {s} (drop)\n", .{fd.name});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  - {s} (drop)\n", .{fd.name});
                    }
                },
                .modify => {
                    // Show what changed: type and modifiers
                    if (fd.old_field) |old_f| {
                        if (fd.new_field) |new_f| {
                            // Check if type changed
                            var old_buf: [64]u8 = undefined;
                            var new_buf: [64]u8 = undefined;
                            const old_type = formatTypeInfo(old_f.type_info, &old_buf);
                            const new_type = formatTypeInfo(new_f.type_info, &new_buf);
                            if (!std.mem.eql(u8, old_type, new_type)) {
                                if (use_color) {
                                    try w.writeAll(color_mod.YELLOW);
                                    try w.print("  ~ {s} (modify: {s} → {s})\n", .{ fd.name, old_type, new_type });
                                    try w.writeAll(color_mod.RESET);
                                } else {
                                    try w.print("  ~ {s} (modify: {s} → {s})\n", .{ fd.name, old_type, new_type });
                                }
                            } else {
                                if (use_color) {
                                    try w.writeAll(color_mod.YELLOW);
                                    try w.print("  ~ {s} (modify)\n", .{fd.name});
                                    try w.writeAll(color_mod.RESET);
                                } else {
                                    try w.print("  ~ {s} (modify)\n", .{fd.name});
                                }
                            }
                        } else {
                            if (use_color) {
                                try w.writeAll(color_mod.YELLOW);
                                try w.print("  ~ {s} (modify)\n", .{fd.name});
                                try w.writeAll(color_mod.RESET);
                            } else {
                                try w.print("  ~ {s} (modify)\n", .{fd.name});
                            }
                        }
                    } else {
                        if (use_color) {
                            try w.writeAll(color_mod.YELLOW);
                            try w.print("  ~ {s} (modify)\n", .{fd.name});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  ~ {s} (modify)\n", .{fd.name});
                        }
                    }
                },
                .rename => {
                    if (use_color) {
                        try w.writeAll(color_mod.YELLOW);
                        try w.print("  ~ {s} → {s} (rename)\n", .{ fd.rename_from.?, fd.name });
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  ~ {s} → {s} (rename)\n", .{ fd.rename_from.?, fd.name });
                    }
                },
            }
        }
        // Metadata diffs (comment, engine)
        if (td.metadata_diff) |md| {
            if (!optionalStrEq(md.old_comment, md.new_comment)) {
                if (!table_has_changes) {
                    if (use_color) {
                        try w.writeAll(color_mod.BLUE ++ color_mod.BOLD);
                        try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    }
                    table_has_changes = true;
                }
                if (md.old_comment) |oc| {
                    if (md.new_comment) |nc| {
                        if (use_color) {
                            try w.writeAll(color_mod.YELLOW);
                            try w.print("  ~ comment: '{s}' → '{s}'\n", .{ oc, nc });
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  ~ comment: '{s}' → '{s}'\n", .{ oc, nc });
                        }
                    } else {
                        if (use_color) {
                            try w.writeAll(color_mod.RED);
                            try w.print("  - comment (removed): '{s}'\n", .{oc});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  - comment (removed): '{s}'\n", .{oc});
                        }
                    }
                } else if (md.new_comment) |nc| {
                    if (use_color) {
                        try w.writeAll(color_mod.GREEN);
                        try w.print("  + comment: '{s}'\n", .{nc});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  + comment: '{s}'\n", .{nc});
                    }
                }
            }
            if (!optionalStrEq(md.old_engine, md.new_engine)) {
                if (!table_has_changes) {
                    if (use_color) {
                        try w.writeAll(color_mod.BLUE ++ color_mod.BOLD);
                        try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    }
                    table_has_changes = true;
                }
                if (md.old_engine) |oe| {
                    if (md.new_engine) |ne| {
                        if (use_color) {
                            try w.writeAll(color_mod.YELLOW);
                            try w.print("  ~ engine: '{s}' → '{s}'\n", .{ oe, ne });
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  ~ engine: '{s}' → '{s}'\n", .{ oe, ne });
                        }
                    } else {
                        if (use_color) {
                            try w.writeAll(color_mod.RED);
                            try w.print("  - engine (removed): '{s}'\n", .{oe});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  - engine (removed): '{s}'\n", .{oe});
                        }
                    }
                } else if (md.new_engine) |ne| {
                    if (use_color) {
                        try w.writeAll(color_mod.GREEN);
                        try w.print("  + engine: '{s}'\n", .{ne});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  + engine: '{s}'\n", .{ne});
                    }
                }
            }
        }
        for (td.index_diffs) |idx| {
            if (!table_has_changes) {
                if (use_color) {
                    try w.writeAll(color_mod.BLUE ++ color_mod.BOLD);
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                }
                table_has_changes = true;
            }
            switch (idx.action) {
                .add => {
                    if (use_color) {
                        try w.writeAll(color_mod.GREEN);
                        try w.print("  + @{s} (add index)\n", .{idx.name});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  + @{s} (add index)\n", .{idx.name});
                    }
                },
                .drop => {
                    if (use_color) {
                        try w.writeAll(color_mod.RED);
                        try w.print("  - @{s} (drop index)\n", .{idx.name});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  - @{s} (drop index)\n", .{idx.name});
                    }
                },
                .modify => {
                    if (use_color) {
                        try w.writeAll(color_mod.YELLOW);
                        try w.print("  ~ @{s} (modify index)\n", .{idx.name});
                        try w.writeAll(color_mod.RESET);
                    } else {
                        try w.print("  ~ @{s} (modify index)\n", .{idx.name});
                    }
                },
            }
        }
        for (td.fk_diffs) |fk| {
            if (!table_has_changes) {
                if (use_color) {
                    try w.writeAll(color_mod.BLUE ++ color_mod.BOLD);
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    try w.writeAll(color_mod.RESET);
                } else {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                }
                table_has_changes = true;
            }
            switch (fk.action) {
                .add => {
                    if (fk.new_fk) |nfk| {
                        if (use_color) {
                            try w.writeAll(color_mod.GREEN);
                            try w.print("  + FK → {s} (add)\n", .{nfk.ref_table});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  + FK → {s} (add)\n", .{nfk.ref_table});
                        }
                    }
                },
                .drop => {
                    if (fk.old_fk) |ofk| {
                        if (use_color) {
                            try w.writeAll(color_mod.RED);
                            try w.print("  - FK → {s} (drop)\n", .{ofk.ref_table});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  - FK → {s} (drop)\n", .{ofk.ref_table});
                        }
                    }
                },
                .modify => {
                    if (fk.new_fk) |nfk| {
                        if (use_color) {
                            try w.writeAll(color_mod.YELLOW);
                            try w.print("  ~ FK → {s} (modify)\n", .{nfk.ref_table});
                            try w.writeAll(color_mod.RESET);
                        } else {
                            try w.print("  ~ FK → {s} (modify)\n", .{nfk.ref_table});
                        }
                    }
                },
            }
        }
    }
}

pub fn formatDiff(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect, color_mode: cli.ColorMode, io: std.Io) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = quoteChar(dialect);
    const use_color = color_mode.shouldUseColor(io);
    try writeDiffTo(w, d, q, use_color);

    // Summary statistics
    const stats = DiffStats.compute(d);
    const total = stats.dropped_tables + stats.added_tables + stats.modified_tables;
    if (total > 0) {
        try w.writeAll("\n");
        if (use_color) {
            try w.writeAll(color_mod.BOLD);
        }
        try w.print("{d} table{s} changed", .{ total, if (total != 1) "s" else "" });
        var parts: usize = 0;
        if (stats.added_tables > 0) {
            if (use_color) try w.writeAll(color_mod.GREEN);
            if (parts > 0) try w.writeAll(", ");
            try w.print("{d} added", .{stats.added_tables});
            if (use_color) try w.writeAll(color_mod.RESET);
            parts += 1;
        }
        if (stats.dropped_tables > 0) {
            if (use_color) try w.writeAll(color_mod.RED);
            if (parts > 0) try w.writeAll(", ");
            try w.print("{d} dropped", .{stats.dropped_tables});
            if (use_color) try w.writeAll(color_mod.RESET);
            parts += 1;
        }
        if (stats.modified_tables > 0) {
            if (use_color) try w.writeAll(color_mod.YELLOW);
            if (parts > 0) try w.writeAll(", ");
            try w.print("{d} modified", .{stats.modified_tables});
            if (use_color) try w.writeAll(color_mod.RESET);
            parts += 1;
        }
        if (use_color) {
            try w.writeAll(color_mod.RESET);
        }
        try w.writeAll("\n");
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

pub fn printDiff(d: SchemaDiff, dialect: Dialect) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const text = formatDiff(arena.allocator(), d, dialect, .never, undefined) catch return;
    std.debug.print("{s}", .{text});
}
