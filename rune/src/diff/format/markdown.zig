const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const dialect_mod = @import("../../dialect/dialect.zig");
const utils = @import("../../utils.zig");
const format_common = @import("../../diff/format_common.zig");
const SchemaDiff = diff_types.SchemaDiff;
const Dialect = @import("../../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;
const DiffStats = format_common.DiffStats;

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

const formatTypeInfo = format_common.formatTypeInfo;

/// Format SchemaDiff as a Markdown table for documentation and PR descriptions.
pub fn formatDiffMarkdown(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = quoteChar(dialect);

    // Header
    try w.writeAll("## Schema Diff\n\n");

    // Summary table
    const stats = DiffStats.compute(d);

    try w.writeAll("| Metric | Count |\n");
    try w.writeAll("|--------|-------|\n");
    try w.print("| Tables added | {d} |\n", .{stats.added_tables});
    try w.print("| Tables dropped | {d} |\n", .{stats.dropped_tables});
    try w.print("| Modifications | {d} |\n", .{stats.modified_tables});
    try w.print("| Fields added | {d} |\n", .{stats.added_fields});
    try w.print("| Fields dropped | {d} |\n", .{stats.dropped_fields});
    if (stats.added_custom_types > 0 or stats.dropped_custom_types > 0 or stats.modified_custom_types > 0) {
        try w.print("| Types added | {d} |\n", .{stats.added_custom_types});
        try w.print("| Types dropped | {d} |\n", .{stats.dropped_custom_types});
        try w.print("| Types modified | {d} |\n", .{stats.modified_custom_types});
    }
    try w.writeAll("\n");

    // Detailed changes per table
    if (d.dropped_tables.len > 0) {
        try w.writeAll("### Dropped Tables\n\n");
        try w.writeAll("| Table |\n");
        try w.writeAll("|-------|\n");
        for (d.dropped_tables) |tname| {
            try w.print("| ~~{c}{s}{c}~~ |\n", .{ q, tname, q });
        }
        try w.writeAll("\n");
    }

    for (d.table_diffs) |td| {
        switch (td.action) {
            .create => {
                try w.print("### + Table `{s}`\n\n", .{td.name});
                try w.print("| Column | Type |\n", .{});
                try w.print("|--------|------|\n", .{});
                for (td.field_diffs) |fd| {
                    var buf: [64]u8 = undefined;
                    const type_str = if (fd.new_field) |nf|
                        formatTypeInfo(nf.type_info, &buf)
                    else
                        "?";
                    try w.print("| + `{s}` | {s} |\n", .{ fd.name, type_str });
                }
                for (td.index_diffs) |idx| {
                    try w.print("| + `@{s}` | index |\n", .{idx.name});
                }
                for (td.fk_diffs) |fk| {
                    if (fk.new_fk) |nfk| {
                        try w.print("| + FK | → `{s}` |\n", .{nfk.ref_table});
                    }
                }
                try w.writeAll("\n");
            },
            .alter => {
                var has_changes = false;
                for (td.field_diffs) |fd| {
                    if (fd.action == .add or fd.action == .drop or fd.action == .modify or fd.action == .rename) {
                        if (!has_changes) {
                            try w.print("### ~ Table `{s}`\n\n", .{td.name});
                            try w.writeAll("| Change | Column | Details |\n");
                            try w.writeAll("|--------|--------|---------|\n");
                            has_changes = true;
                        }
                        switch (fd.action) {
                            .add => {
                                var buf: [64]u8 = undefined;
                                const type_str = if (fd.new_field) |nf|
                                    formatTypeInfo(nf.type_info, &buf)
                                else
                                    "?";
                                try w.print("| + | `{s}` | {s} |\n", .{ fd.name, type_str });
                            },
                            .drop => try w.print("| - | `{s}` | removed |\n", .{fd.name}),
                            .modify => {
                                if (fd.old_field) |old_f| {
                                    if (fd.new_field) |new_f| {
                                        var old_buf: [64]u8 = undefined;
                                        var new_buf: [64]u8 = undefined;
                                        const old_type = formatTypeInfo(old_f.type_info, &old_buf);
                                        const new_type = formatTypeInfo(new_f.type_info, &new_buf);
                                        if (!std.mem.eql(u8, old_type, new_type)) {
                                            try w.print("| ~ | `{s}` | {s} → {s} |\n", .{ fd.name, old_type, new_type });
                                        } else {
                                            try w.print("| ~ | `{s}` | modified |\n", .{fd.name});
                                        }
                                    }
                                }
                            },
                            .rename => try w.print("| ~ | `{s}` | renamed from `{s}` |\n", .{ fd.name, fd.rename_from.? }),
                        }
                    }
                }
                // Index changes
                for (td.index_diffs) |idx| {
                    if (!has_changes) {
                        try w.print("### ~ Table `{s}`\n\n", .{td.name});
                        try w.writeAll("| Change | Column | Details |\n");
                        try w.writeAll("|--------|--------|---------|\n");
                        has_changes = true;
                    }
                    switch (idx.action) {
                        .add => try w.print("| + | `@{s}` | index |\n", .{idx.name}),
                        .drop => try w.print("| - | `@{s}` | index |\n", .{idx.name}),
                        .modify => try w.print("| ~ | `@{s}` | index |\n", .{idx.name}),
                    }
                }
                // FK changes
                for (td.fk_diffs) |fk| {
                    if (!has_changes) {
                        try w.print("### ~ Table `{s}`\n\n", .{td.name});
                        try w.writeAll("| Change | Column | Details |\n");
                        try w.writeAll("|--------|--------|---------|\n");
                        has_changes = true;
                    }
                    switch (fk.action) {
                        .add => {
                            if (fk.new_fk) |nfk| {
                                try w.print("| + | FK | → `{s}` |\n", .{nfk.ref_table});
                            }
                        },
                        .drop => {
                            if (fk.old_fk) |ofk| {
                                try w.print("| - | FK | → `{s}` |\n", .{ofk.ref_table});
                            }
                        },
                        .modify => {
                            if (fk.new_fk) |nfk| {
                                try w.print("| ~ | FK | → `{s}` |\n", .{nfk.ref_table});
                            }
                        },
                    }
                }
                if (has_changes) {
                    try w.writeAll("\n");
                }
            },
        }
    }

    // View diffs
    for (d.view_diffs) |vd| {
        switch (vd.action) {
            .create => try w.print("### + View `{s}`\n\n", .{vd.name}),
            .drop => try w.print("### - View `{s}`\n\n", .{vd.name}),
            .modify => try w.print("### ~ View `{s}` (query changed)\n\n", .{vd.name}),
        }
    }

    try w.flush();
    return try aw.toOwnedSlice();
}
