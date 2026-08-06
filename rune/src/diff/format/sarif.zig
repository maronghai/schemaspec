const std = @import("std");
const diff_types = @import("../../diff/types.zig");
const dialect_mod = @import("../../dialect/dialect.zig");
const utils = @import("../../utils.zig");
const version = @import("../../version.zig");
const SchemaDiff = diff_types.SchemaDiff;
const Dialect = @import("../../dialect/enum.zig").Dialect;

const jsonEscapeString = utils.jsonEscapeString;

fn quoteChar(dialect: Dialect) u8 {
    return dialect_mod.getBackend(dialect).quoteChar;
}

/// Format SchemaDiff as SARIF (Static Analysis Results Interchange Format) for CI/CD integration.
pub fn formatDiffSarif(alloc: std.mem.Allocator, d: SchemaDiff, dialect: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = quoteChar(dialect);

    try w.writeAll("{\n");
    try w.writeAll("  \"$schema\": \"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\n");
    try w.writeAll("  \"version\": \"2.1.0\",\n");
    try w.writeAll("  \"runs\": [{\n");
    try w.writeAll("    \"tool\": {\n");
    try w.writeAll("      \"driver\": {\n");
    try w.writeAll("        \"name\": \"rune\",\n");
    try w.writeAll("        \"informationUri\": \"https://github.com/rune-lang/rune\",\n");
    try w.print("        \"version\": \"{s}\"\n", .{version.VERSION});
    try w.writeAll("      }\n");
    try w.writeAll("    },\n");
    try w.writeAll("    \"results\": [\n");

    var result_idx: usize = 0;

    // Dropped tables
    for (d.dropped_tables) |tname| {
        if (result_idx > 0) try w.writeAll(",\n");
        try w.writeAll("      {\n");
        try w.writeAll("        \"ruleId\": \"schema/dropped-table\",\n");
        try w.writeAll("        \"level\": \"warning\",\n");
        try w.writeAll("        \"message\": {\n");
        try w.writeAll("          \"text\": \"Table dropped: ");
        try w.writeByte(q);
        try jsonEscapeString(w, tname);
        try w.writeByte(q);
        try w.writeAll("\"\n");
        try w.writeAll("        },\n");
        try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
        try w.writeAll("      }");
        result_idx += 1;
    }

    // View diffs
    for (d.view_diffs) |vd| {
        if (result_idx > 0) try w.writeAll(",\n");
        try w.writeAll("      {\n");
        try w.writeAll("        \"ruleId\": \"schema/view-");
        try w.writeAll(@tagName(vd.action));
        try w.writeAll("\",\n");
        try w.writeAll("        \"level\": \"note\",\n");
        try w.writeAll("        \"message\": {\n");
        try w.writeAll("          \"text\": \"View ");
        try w.writeAll(@tagName(vd.action));
        try w.writeAll(": ");
        try w.writeByte(q);
        try jsonEscapeString(w, vd.name);
        try w.writeByte(q);
        try w.writeAll("\"\n");
        try w.writeAll("        },\n");
        try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
        try w.writeAll("      }");
        result_idx += 1;
    }

    // Table diffs
    for (d.table_diffs) |td| {
        if (td.action == .create) {
            if (result_idx > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.writeAll("        \"ruleId\": \"schema/created-table\",\n");
            try w.writeAll("        \"level\": \"note\",\n");
            try w.writeAll("        \"message\": {\n");
            try w.writeAll("          \"text\": \"Table created: ");
            try w.writeByte(q);
            try jsonEscapeString(w, td.name);
            try w.writeByte(q);
            try w.writeAll("\"\n");
            try w.writeAll("        },\n");
            try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
            try w.writeAll("      }");
            result_idx += 1;
            continue;
        }

        // Field diffs within altered table
        for (td.field_diffs) |fd| {
            if (result_idx > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.writeAll("        \"ruleId\": \"schema/field-");
            try w.writeAll(@tagName(fd.action));
            try w.writeAll("\",\n");
            try w.writeAll("        \"level\": \"note\",\n");
            try w.writeAll("        \"message\": {\n");
            try w.writeAll("          \"text\": \"Field ");
            try w.writeAll(@tagName(fd.action));
            try w.writeAll(" in ");
            try w.writeByte(q);
            try jsonEscapeString(w, td.name);
            try w.writeByte(q);
            try w.writeAll(": ");
            try jsonEscapeString(w, fd.name);
            try w.writeAll("\"\n");
            try w.writeAll("        },\n");
            try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
            try w.writeAll("      }");
            result_idx += 1;
        }

        // Index diffs
        for (td.index_diffs) |idx| {
            if (result_idx > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.writeAll("        \"ruleId\": \"schema/index-");
            try w.writeAll(@tagName(idx.action));
            try w.writeAll("\",\n");
            try w.writeAll("        \"level\": \"note\",\n");
            try w.writeAll("        \"message\": {\n");
            try w.writeAll("          \"text\": \"Index ");
            try w.writeAll(@tagName(idx.action));
            try w.writeAll(" in ");
            try w.writeByte(q);
            try jsonEscapeString(w, td.name);
            try w.writeByte(q);
            try w.writeAll(": ");
            try jsonEscapeString(w, idx.name);
            try w.writeAll("\"\n");
            try w.writeAll("        },\n");
            try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
            try w.writeAll("      }");
            result_idx += 1;
        }

        // FK diffs
        for (td.fk_diffs) |fk| {
            if (result_idx > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.writeAll("        \"ruleId\": \"schema/fk-");
            try w.writeAll(@tagName(fk.action));
            try w.writeAll("\",\n");
            try w.writeAll("        \"level\": \"note\",\n");
            try w.writeAll("        \"message\": {\n");
            try w.writeAll("          \"text\": \"Foreign key ");
            try w.writeAll(@tagName(fk.action));
            try w.writeAll(" in ");
            try w.writeByte(q);
            try jsonEscapeString(w, td.name);
            try w.writeByte(q);
            try w.writeAll("\"");
            if (fk.new_fk) |nfk| {
                try w.writeAll(" referencing ");
                try jsonEscapeString(w, nfk.ref_table);
            }
            try w.writeAll("\",\n");
            try w.writeAll("        },\n");
            try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
            try w.writeAll("      }");
            result_idx += 1;
        }

        // Metadata diffs
        if (td.metadata_diff) |md| {
            if (md.hasChanges()) {
                if (!@import("../../utils.zig").optionalStrEq(md.old_comment, md.new_comment)) {
                    if (result_idx > 0) try w.writeAll(",\n");
                    try w.writeAll("      {\n");
                    try w.writeAll("        \"ruleId\": \"schema/metadata-comment\",\n");
                    try w.writeAll("        \"level\": \"note\",\n");
                    try w.writeAll("        \"message\": {\n");
                    try w.writeAll("          \"text\": \"Table comment changed in ");
                    try w.writeByte(q);
                    try jsonEscapeString(w, td.name);
                    try w.writeByte(q);
                    try w.writeAll("\"\n");
                    try w.writeAll("        },\n");
                    try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
                    try w.writeAll("      }");
                    result_idx += 1;
                }
                if (!@import("../../utils.zig").optionalStrEq(md.old_engine, md.new_engine)) {
                    if (result_idx > 0) try w.writeAll(",\n");
                    try w.writeAll("      {\n");
                    try w.writeAll("        \"ruleId\": \"schema/metadata-engine\",\n");
                    try w.writeAll("        \"level\": \"note\",\n");
                    try w.writeAll("        \"message\": {\n");
                    try w.writeAll("          \"text\": \"Table engine changed in ");
                    try w.writeByte(q);
                    try jsonEscapeString(w, td.name);
                    try w.writeByte(q);
                    try w.writeAll("\"\n");
                    try w.writeAll("        },\n");
                    try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
                    try w.writeAll("      }");
                    result_idx += 1;
                }
            }
        }
    }

    if (result_idx == 0) {
        try w.writeAll("      ");
    }
    try w.writeAll("\n    ]\n");
    try w.writeAll("  }]\n");
    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}
