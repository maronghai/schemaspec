const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const diff_types = @import("types.zig");
const color_mod = @import("../color.zig");
const utils = @import("../utils.zig");
const SchemaDiff = diff_types.SchemaDiff;

const optionalStrEq = utils.optionalStrEq;

// ─── Shared Helpers ────────────────────────────────────────────

/// Write text with optional ANSI color wrapping.
pub fn writeColorized(w: anytype, color: []const u8, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) try w.writeAll(color);
    try w.print(fmt, args);
    if (use_color) try w.writeAll(color_mod.RESET);
}

/// Format TypeInfo to a user-friendly string representation.
/// Shared by text and markdown diff formatters.
pub fn formatTypeInfo(info: ast_mod.TypeInfo, buf: []u8) []const u8 {
    return switch (info) {
        .none => "any",
        .simple => |s| s,
        .int_explicit => |n| {
            const len = std.fmt.bufPrint(buf, "int({d})", .{n}) catch return "int";
            return len;
        },
        .decimal_explicit => |ds| {
            const len = std.fmt.bufPrint(buf, "decimal({d},{d})", .{ ds.precision, ds.scale }) catch return "decimal";
            return len;
        },
        .varchar_explicit => |n| {
            const len = std.fmt.bufPrint(buf, "varchar({d})", .{n}) catch return "varchar";
            return len;
        },
        .enum_type => "enum",
        .raw_sql => |s| s,
    };
}

// ─── Diff Statistics ──────────────────────────────────────────

/// Count diff statistics for summary output.
pub const DiffStats = struct {
    dropped_tables: usize = 0,
    added_tables: usize = 0,
    modified_tables: usize = 0,
    added_fields: usize = 0,
    dropped_fields: usize = 0,

    pub fn compute(d: SchemaDiff) DiffStats {
        var stats = DiffStats{};
        stats.dropped_tables = d.dropped_tables.len;
        for (d.table_diffs) |td| {
            switch (td.action) {
                .create => stats.added_tables += 1,
                .alter => {
                    var has_changes = false;
                    for (td.field_diffs) |fd| {
                        switch (fd.action) {
                            .add => {
                                stats.added_fields += 1;
                                has_changes = true;
                            },
                            .drop => {
                                stats.dropped_fields += 1;
                                has_changes = true;
                            },
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

/// Write the summary statistics line to a writer with optional color.
/// Used by both `formatDiff` and `formatDiffSummary` in text.zig.
pub fn formatSummaryStats(w: anytype, stats: DiffStats, use_color: bool) !void {
    const total = stats.dropped_tables + stats.added_tables + stats.modified_tables;
    if (total == 0) {
        try w.writeAll("no changes\n");
        return;
    }
    if (use_color) try w.writeAll(color_mod.BOLD);
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
    if (use_color) try w.writeAll(color_mod.RESET);
    try w.writeAll("\n");
}
