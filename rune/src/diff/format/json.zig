const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const utils = @import("../../utils.zig");
const SchemaDiff = diff_types.SchemaDiff;

const jsonEscapeString = utils.jsonEscapeString;

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
        if (td.rename_from) |old_name| {
            try w.writeAll("    \"rename_from\": \"");
            try jsonEscapeString(w, old_name);
            try w.writeAll("\",\n");
        }

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

        // metadata_diff
        if (td.metadata_diff) |md| {
            if (md.hasChanges()) {
                try w.writeAll(",\n    \"metadata_diff\": {");
                var first = true;
                if (!utils.optionalStrEq(md.old_comment, md.new_comment)) {
                    if (!first) try w.writeAll(",");
                    first = false;
                    try w.writeAll("\n      \"comment\": {");
                    try w.writeAll("\n        \"old\": ");
                    if (md.old_comment) |oc| {
                        try w.writeByte('"');
                        try jsonEscapeString(w, oc);
                        try w.writeByte('"');
                    } else {
                        try w.writeAll("null");
                    }
                    try w.writeAll(",\n        \"new\": ");
                    if (md.new_comment) |nc| {
                        try w.writeByte('"');
                        try jsonEscapeString(w, nc);
                        try w.writeByte('"');
                    } else {
                        try w.writeAll("null");
                    }
                    try w.writeAll("\n      }");
                }
                if (!utils.optionalStrEq(md.old_engine, md.new_engine)) {
                    if (!first) try w.writeAll(",");
                    first = false;
                    try w.writeAll("\n      \"engine\": {");
                    try w.writeAll("\n        \"old\": ");
                    if (md.old_engine) |oe| {
                        try w.writeByte('"');
                        try jsonEscapeString(w, oe);
                        try w.writeByte('"');
                    } else {
                        try w.writeAll("null");
                    }
                    try w.writeAll(",\n        \"new\": ");
                    if (md.new_engine) |ne| {
                        try w.writeByte('"');
                        try jsonEscapeString(w, ne);
                        try w.writeByte('"');
                    } else {
                        try w.writeAll("null");
                    }
                    try w.writeAll("\n      }");
                }
                try w.writeAll("\n    }");
            }
        }

        try w.writeAll("\n  }");
    }
    try w.writeAll("]\n");

    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}
