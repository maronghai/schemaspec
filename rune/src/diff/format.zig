const std = @import("std");
const diff_types = @import("../diff/types.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const utils = @import("../utils.zig");
const SchemaDiff = diff_types.SchemaDiff;
const TableDiff = diff_types.TableDiff;
const Dialect = @import("../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;
const jsonEscapeString = utils.jsonEscapeString;

// ─── Diff Formatter ──────────────────────────────────────────
//
// Renders SchemaDiff as human-readable text for `rune diff`.
// Separated from diff.zig to allow alternative output formats
// (JSON, machine-readable) without modifying the diff engine.

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

/// Core diff formatting logic — writes to any std.io.Writer.
fn writeDiffTo(w: anytype, d: SchemaDiff, q: u8) !void {
    var has_changes = false;

    for (d.dropped_tables) |tname| {
        try w.print("-- DROP TABLE {c}{s}{c}\n", .{ q, tname, q });
        has_changes = true;
    }

    for (d.view_diffs) |vd| {
        switch (vd.action) {
            .create => {
                try w.print("-- CREATE VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                has_changes = true;
            },
            .drop => {
                try w.print("-- DROP VIEW {c}{s}{c}\n", .{ q, vd.name, q });
                has_changes = true;
            },
            .modify => {
                try w.print("-- ALTER VIEW {c}{s}{c} (query changed)\n", .{ q, vd.name, q });
                has_changes = true;
            },
        }
    }

    for (d.table_diffs) |td| {
        if (td.action == .create) {
            try w.print("-- CREATE TABLE {c}{s}{c}\n", .{ q, td.name, q });
            has_changes = true;
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
                .modify => try w.print("  ~ {s} (modify)\n", .{fd.name}),
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
                if (md.new_comment) |nc| {
                    try w.print("  ~ comment → '{s}'\n", .{nc});
                } else {
                    try w.print("  - comment (removed)\n", .{});
                }
            }
            if (!optionalStrEq(md.old_engine, md.new_engine)) {
                if (!table_has_changes) {
                    try w.print("-- ALTER TABLE {c}{s}{c}\n", .{ q, td.name, q });
                    table_has_changes = true;
                }
                if (md.new_engine) |ne| {
                    try w.print("  ~ engine → '{s}'\n", .{ne});
                } else {
                    try w.print("  - engine (removed)\n", .{});
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
        if (table_has_changes) has_changes = true;
    }
}

pub fn formatDiff(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = quoteChar(dialect);
    try writeDiffTo(w, d, q);
    try w.flush();
    var out = aw.toArrayList();
    return try out.toOwnedSlice(alloc);
}

pub fn printDiff(d: SchemaDiff, dialect: Dialect) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const text = formatDiff(arena.allocator(), d, dialect) catch return;
    std.debug.print("{s}", .{text});
}

// ─── JSON Diff Output ────────────────────────────────────────────

/// Format SchemaDiff as a JSON string for programmatic consumption.
pub fn formatDiffJson(alloc: std.mem.Allocator, d: SchemaDiff) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");

    // dropped_tables
    try w.writeAll("  \"dropped_tables\": [");
    for (d.dropped_tables, 0..) |tname, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeByte('"');
        try jsonEscapeString(w, tname);
        try w.writeByte('"');
    }
    try w.writeAll("],\n");

    // view_diffs
    try w.writeAll("  \"view_diffs\": [");
    for (d.view_diffs, 0..) |vd, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll("{\"name\": \"");
        try jsonEscapeString(w, vd.name);
        try w.print("\", \"action\": \"{s}\"}}", .{@tagName(vd.action)});
    }
    try w.writeAll("],\n");

    // table_diffs
    try w.writeAll("  \"table_diffs\": [");
    for (d.table_diffs, 0..) |td, ti| {
        if (ti > 0) try w.writeAll(", ");
        try w.writeAll("{\n");
        try w.writeAll("    \"name\": \"");
        try jsonEscapeString(w, td.name);
        try w.writeAll("\",\n");
        try w.print("    \"action\": \"{s}\",\n", .{@tagName(td.action)});

        // field_diffs
        try w.writeAll("    \"field_diffs\": [");
        for (td.field_diffs, 0..) |fd, fi| {
            if (fi > 0) try w.writeAll(", ");
            try w.writeAll("{\"name\": \"");
            try jsonEscapeString(w, fd.name);
            try w.writeAll("\", \"action\": \"");
            try w.writeAll(@tagName(fd.action));
            try w.writeAll("\"");
            if (fd.rename_from) |rf| {
                try w.writeAll(", \"from\": \"");
                try jsonEscapeString(w, rf);
                try w.writeByte('"');
            }
            try w.writeAll("}");
        }
        try w.writeAll("],\n");

        // index_diffs
        try w.writeAll("    \"index_diffs\": [");
        for (td.index_diffs, 0..) |idx, ii| {
            if (ii > 0) try w.writeAll(", ");
            try w.writeAll("{\"name\": \"");
            try jsonEscapeString(w, idx.name);
            try w.print("\", \"action\": \"{s}\"}}", .{@tagName(idx.action)});
        }
        try w.writeAll("],\n");

        // fk_diffs
        try w.writeAll("    \"fk_diffs\": [");
        for (td.fk_diffs, 0..) |fk, fi| {
            if (fi > 0) try w.writeAll(", ");
            try w.writeAll("{\"action\": \"");
            try w.writeAll(@tagName(fk.action));
            try w.writeAll("\"");
            if (fk.new_fk) |nfk| {
                try w.writeAll(", \"ref_table\": \"");
                try jsonEscapeString(w, nfk.ref_table);
                try w.writeByte('"');
            }
            try w.writeAll("}");
        }
        try w.writeAll("]");

        try w.writeAll("\n  }");
    }
    try w.writeAll("]\n");

    try w.writeAll("}\n");

    try w.flush();
    var out = aw.toArrayList();
    return try out.toOwnedSlice(alloc);
}
