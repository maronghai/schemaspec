const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const dialect_mod = @import("../../dialect/dialect.zig");
const utils = @import("../../utils.zig");
const format_common = @import("../../diff/format_common.zig");
const ColorMode = @import("../../types/enums.zig").ColorMode;
const color_mod = @import("../../color.zig");
const SchemaDiff = diff_types.SchemaDiff;
const Dialect = @import("../../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;
const writeColorized = format_common.writeColorized;
const DiffStats = format_common.DiffStats;
const formatSummaryStats = format_common.formatSummaryStats;

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

const formatTypeInfo = format_common.formatTypeInfo;

/// Emit the `-- ALTER TABLE` header if not already emitted for this table.
fn emitAlterTableHeader(w: anytype, name: []const u8, q: u8, use_color: bool, has_changes: *bool) !void {
    if (!has_changes.*) {
        try writeColorized(w, color_mod.BLUE ++ color_mod.BOLD, use_color, "-- ALTER TABLE {c}{s}{c}\n", .{ q, name, q });
        has_changes.* = true;
    }
}

/// Core diff formatting logic — writes to any std.io.Writer with optional ANSI color support.
pub fn writeDiffTo(w: anytype, d: SchemaDiff, q: u8, use_color: bool) !void {
    for (d.dropped_tables) |tname| {
        try writeColorized(w, color_mod.RED, use_color, "-- DROP TABLE {c}{s}{c}\n", .{ q, tname, q });
    }

    for (d.view_diffs) |vd| {
        const color = switch (vd.action) {
            .create => color_mod.GREEN,
            .drop => color_mod.RED,
            .modify => color_mod.YELLOW,
        };
        const label = switch (vd.action) {
            .create => "CREATE VIEW",
            .drop => "DROP VIEW",
            .modify => "ALTER VIEW",
        };
        const suffix = if (vd.action == .modify) " (query changed)" else "";
        try writeColorized(w, color, use_color, "-- {s} {c}{s}{c}{s}\n", .{ label, q, vd.name, q, suffix });
    }

    for (d.custom_type_diffs) |ctd| {
        const color = switch (ctd.action) {
            .add => color_mod.GREEN,
            .drop => color_mod.RED,
            .modify => color_mod.YELLOW,
        };
        const label = switch (ctd.action) {
            .add => "CREATE TYPE",
            .drop => "DROP TYPE",
            .modify => "ALTER TYPE",
        };
        try writeColorized(w, color, use_color, "-- {s} {c}{s}{c}\n", .{ label, q, ctd.name, q });
    }

    for (d.table_diffs) |td| {
        if (td.action == .create) {
            try writeColorized(w, color_mod.GREEN, use_color, "-- CREATE TABLE {c}{s}{c}\n", .{ q, td.name, q });
            for (td.field_diffs) |fd| {
                try writeColorized(w, color_mod.GREEN, use_color, "  + {s}\n", .{fd.name});
            }
            for (td.index_diffs) |idx| {
                try writeColorized(w, color_mod.GREEN, use_color, "  + @{s}\n", .{idx.name});
            }
            for (td.fk_diffs) |fk| {
                if (fk.new_fk) |nfk| {
                    try writeColorized(w, color_mod.GREEN, use_color, "  + FK → {s}\n", .{nfk.ref_table});
                }
            }
            continue;
        }

        // alter
        if (td.rename_from) |old_name| {
            // Table rename: show rename header
            try writeColorized(w, color_mod.YELLOW, use_color, "-- RENAME TABLE {c}{s}{c} → {c}{s}{c}\n", .{ q, old_name, q, q, td.name, q });
        }
        var table_has_changes = td.rename_from != null;
        for (td.field_diffs) |fd| {
            try emitAlterTableHeader(w, td.name, q, use_color, &table_has_changes);
            switch (fd.action) {
                .add => {
                    try writeColorized(w, color_mod.GREEN, use_color, "  + {s} (add)\n", .{fd.name});
                },
                .drop => {
                    try writeColorized(w, color_mod.RED, use_color, "  - {s} (drop)\n", .{fd.name});
                },
                .modify => {
                    // Show what changed: type and modifiers
                    if (fd.old_field) |old_f| {
                        if (fd.new_field) |new_f| {
                            var old_buf: [64]u8 = undefined;
                            var new_buf: [64]u8 = undefined;
                            const old_type = formatTypeInfo(old_f.type_info, &old_buf);
                            const new_type = formatTypeInfo(new_f.type_info, &new_buf);
                            if (!std.mem.eql(u8, old_type, new_type)) {
                                try writeColorized(w, color_mod.YELLOW, use_color, "  ~ {s} (modify: {s} → {s})\n", .{ fd.name, old_type, new_type });
                            } else {
                                try writeColorized(w, color_mod.YELLOW, use_color, "  ~ {s} (modify)\n", .{fd.name});
                            }
                        } else {
                            try writeColorized(w, color_mod.YELLOW, use_color, "  ~ {s} (modify)\n", .{fd.name});
                        }
                    } else {
                        try writeColorized(w, color_mod.YELLOW, use_color, "  ~ {s} (modify)\n", .{fd.name});
                    }
                },
                .rename => {
                    try writeColorized(w, color_mod.YELLOW, use_color, "  ~ {s} → {s} (rename)\n", .{ fd.rename_from.?, fd.name });
                },
            }
        }
        // Metadata diffs (comment, engine)
        if (td.metadata_diff) |md| {
            if (!optionalStrEq(md.old_comment, md.new_comment)) {
                try emitAlterTableHeader(w, td.name, q, use_color, &table_has_changes);
                if (md.old_comment) |oc| {
                    if (md.new_comment) |nc| {
                        try writeColorized(w, color_mod.YELLOW, use_color, "  ~ comment: '{s}' → '{s}'\n", .{ oc, nc });
                    } else {
                        try writeColorized(w, color_mod.RED, use_color, "  - comment (removed): '{s}'\n", .{oc});
                    }
                } else if (md.new_comment) |nc| {
                    try writeColorized(w, color_mod.GREEN, use_color, "  + comment: '{s}'\n", .{nc});
                }
            }
            if (!optionalStrEq(md.old_engine, md.new_engine)) {
                try emitAlterTableHeader(w, td.name, q, use_color, &table_has_changes);
                if (md.old_engine) |oe| {
                    if (md.new_engine) |ne| {
                        try writeColorized(w, color_mod.YELLOW, use_color, "  ~ engine: '{s}' → '{s}'\n", .{ oe, ne });
                    } else {
                        try writeColorized(w, color_mod.RED, use_color, "  - engine (removed): '{s}'\n", .{oe});
                    }
                } else if (md.new_engine) |ne| {
                    try writeColorized(w, color_mod.GREEN, use_color, "  + engine: '{s}'\n", .{ne});
                }
            }
        }
        for (td.index_diffs) |idx| {
            try emitAlterTableHeader(w, td.name, q, use_color, &table_has_changes);
            const color = switch (idx.action) {
                .add => color_mod.GREEN,
                .drop => color_mod.RED,
                .modify => color_mod.YELLOW,
            };
            const label = switch (idx.action) {
                .add => "+",
                .drop => "-",
                .modify => "~",
            };
            try writeColorized(w, color, use_color, "  {s} @{s} ({s} index)\n", .{ label, idx.name, @tagName(idx.action) });
        }
        for (td.fk_diffs) |fk| {
            try emitAlterTableHeader(w, td.name, q, use_color, &table_has_changes);
            switch (fk.action) {
                .add => {
                    if (fk.new_fk) |nfk| {
                        try writeColorized(w, color_mod.GREEN, use_color, "  + FK → {s} (add)\n", .{nfk.ref_table});
                    }
                },
                .drop => {
                    if (fk.old_fk) |ofk| {
                        try writeColorized(w, color_mod.RED, use_color, "  - FK → {s} (drop)\n", .{ofk.ref_table});
                    }
                },
                .modify => {
                    if (fk.new_fk) |nfk| {
                        try writeColorized(w, color_mod.YELLOW, use_color, "  ~ FK → {s} (modify)\n", .{nfk.ref_table});
                    }
                },
            }
        }
    }
}

pub fn formatDiff(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect, color_mode: ColorMode, io: std.Io) ![]const u8 {
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
        try formatSummaryStats(w, stats, use_color);
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

/// Format only the summary line for `rune diff --summary`.
/// Outputs: "N tables changed (X added, Y dropped, Z modified)"
pub fn formatDiffSummary(alloc: std.mem.Allocator, d: SchemaDiff, color_mode: ColorMode, io: std.Io) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const use_color = color_mode.shouldUseColor(io);
    const stats = DiffStats.compute(d);
    try formatSummaryStats(w, stats, use_color);
    try w.flush();
    return try aw.toOwnedSlice();
}

pub fn printDiff(d: SchemaDiff, dialect: Dialect) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const text = formatDiff(arena.allocator(), d, dialect, .never, undefined) catch return;
    std.debug.print("{s}", .{text});
}
