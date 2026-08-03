const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const dialect_mod = @import("../../dialect/dialect.zig");
const utils = @import("../../utils.zig");
const format_common = @import("../../diff/format_common.zig");
const SchemaDiff = diff_types.SchemaDiff;
const Dialect = @import("../../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

const formatTypeInfo = format_common.formatTypeInfo;

/// Core diff formatting logic — writes to any std.io.Writer.
pub fn writeDiffTo(w: anytype, d: SchemaDiff, q: u8) !void {
    for (d.dropped_tables) |tname| {
        try w.print("-- DROP TABLE {c}{s}{c}\n", .{ q, tname, q });
    }

    for (d.view_diffs) |vd| {
        switch (vd.action) {
            .create => {
                try w.print("-- CREATE VIEW {c}{s}{c}\n", .{ q, vd.name, q });
            },
            .drop => {
                try w.print("-- DROP VIEW {c}{s}{c}\n", .{ q, vd.name, q });
            },
            .modify => {
                try w.print("-- ALTER VIEW {c}{s}{c} (query changed)\n", .{ q, vd.name, q });
            },
        }
    }

    for (d.table_diffs) |td| {
        if (td.action == .create) {
            try w.print("-- CREATE TABLE {c}{s}{c}\n", .{ q, td.name, q });
            for (td.field_diffs) |fd| {
                try w.print("  + {s}\n", .{fd.name});
            }
            for (td.index_diffs) |idx| {
                try w.print("  + @{s}\n", .{idx.name});
            }
            for (td.fk_diffs) |fk| {
                if (fk.new_fk) |nfk| {
                    try w.print("  + FK → {s}\n", .{nfk.ref_table});
                }
            }
            continue;
        }

        // alter
        var table_has_changes = false;
        for (td.field_diffs) |fd| {
            if (!table_has_changes) {
                try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                table_has_changes = true;
            }
            switch (fd.action) {
                .add => try w.print("  + {s} (add)\n", .{fd.name}),
                .drop => try w.print("  - {s} (drop)\n", .{fd.name}),
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
                                try w.print("  ~ {s} (modify: {s} → {s})\n", .{ fd.name, old_type, new_type });
                            } else {
                                try w.print("  ~ {s} (modify)\n", .{fd.name});
                            }
                        } else {
                            try w.print("  ~ {s} (modify)\n", .{fd.name});
                        }
                    } else {
                        try w.print("  ~ {s} (modify)\n", .{fd.name});
                    }
                },
                .rename => try w.print("  ~ {s} → {s} (rename)\n", .{ fd.rename_from.?, fd.name }),
            }
        }
        // Metadata diffs (comment, engine)
        if (td.metadata_diff) |md| {
            if (!optionalStrEq(md.old_comment, md.new_comment)) {
                if (!table_has_changes) {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    table_has_changes = true;
                }
                if (md.old_comment) |oc| {
                    if (md.new_comment) |nc| {
                        try w.print("  ~ comment: '{s}' → '{s}'\n", .{ oc, nc });
                    } else {
                        try w.print("  - comment (removed): '{s}'\n", .{oc});
                    }
                } else if (md.new_comment) |nc| {
                    try w.print("  + comment: '{s}'\n", .{nc});
                }
            }
            if (!optionalStrEq(md.old_engine, md.new_engine)) {
                if (!table_has_changes) {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    table_has_changes = true;
                }
                if (md.old_engine) |oe| {
                    if (md.new_engine) |ne| {
                        try w.print("  ~ engine: '{s}' → '{s}'\n", .{ oe, ne });
                    } else {
                        try w.print("  - engine (removed): '{s}'\n", .{oe});
                    }
                } else if (md.new_engine) |ne| {
                    try w.print("  + engine: '{s}'\n", .{ne});
                }
            }
        }
        for (td.index_diffs) |idx| {
            if (!table_has_changes) {
                try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                table_has_changes = true;
            }
            switch (idx.action) {
                .add => try w.print("  + @{s} (add index)\n", .{idx.name}),
                .drop => try w.print("  - @{s} (drop index)\n", .{idx.name}),
                .modify => try w.print("  ~ @{s} (modify index)\n", .{idx.name}),
            }
        }
        for (td.fk_diffs) |fk| {
            if (!table_has_changes) {
                try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                table_has_changes = true;
            }
            switch (fk.action) {
                .add => {
                    if (fk.new_fk) |nfk| {
                        try w.print("  + FK → {s} (add)\n", .{nfk.ref_table});
                    }
                },
                .drop => {
                    if (fk.old_fk) |ofk| {
                        try w.print("  - FK → {s} (drop)\n", .{ofk.ref_table});
                    }
                },
                .modify => {
                    if (fk.new_fk) |nfk| {
                        try w.print("  ~ FK → {s} (modify)\n", .{nfk.ref_table});
                    }
                },
            }
        }
    }
}

pub fn formatDiff(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = quoteChar(dialect);
    try writeDiffTo(w, d, q);
    try w.flush();
    return try aw.toOwnedSlice();
}

pub fn printDiff(d: SchemaDiff, dialect: Dialect) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const text = formatDiff(arena.allocator(), d, dialect) catch return;
    std.debug.print("{s}", .{text});
}
