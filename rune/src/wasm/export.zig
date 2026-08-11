const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const common = @import("common.zig");
const Writer = std.Io.Writer;

// ─── WASM Export Exports ────────────────────────────────────────
// Export schema as structured data (JSON, text, or Markdown).

/// Export schema as JSON/text/markdown via WASM.
/// Options: "format=json|text|markdown dialect=<dialect>".
pub export fn rune_export(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const format_str = common.parseOption(options, "format") orelse "json";

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types
    const typed = TypeResolver.resolve(alloc, result.resolved, dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Generate export based on format
    const output = if (std.mem.eql(u8, format_str, "markdown"))
        generateMarkdownExport(alloc, typed) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        }
    else if (std.mem.eql(u8, format_str, "text"))
        generateTextExport(alloc, typed) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        }
    else
        generateJsonExport(alloc, typed) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

fn generateJsonExport(alloc: std.mem.Allocator, typed: anytype) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\"tables\":[");
    for (typed.tables, 0..) |table, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeByte('{');
        try writeJsonField(w, "name", table.name);
        try w.writeAll(",\"fields\":[");
        for (table.columns, 0..) |col, j| {
            if (j > 0) try w.writeByte(',');
            try w.writeByte('{');
            try writeJsonField(w, "name", col.name);
            try w.writeAll(",\"type\":");
            try writeJsonString(w, @tagName(col.sql_type));
            try w.writeAll("}");
        }
        try w.writeAll("],\"indexes\":[");
        for (table.indexes, 0..) |idx, j| {
            if (j > 0) try w.writeByte(',');
            try w.writeByte('{');
            try writeJsonField(w, "name", idx.name);
            try w.writeAll("}");
        }
        try w.writeAll("],\"fks\":[");
        for (table.fks, 0..) |fk, j| {
            if (j > 0) try w.writeByte(',');
            try w.writeByte('{');
            try w.writeAll("\"table\":");
            try writeJsonString(w, fk.ref_table);
            try w.writeAll("}");
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]}");
    return try aw.toOwnedSlice();
}

fn generateTextExport(alloc: std.mem.Allocator, typed: anytype) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.print("Schema: {d} tables\n", .{typed.tables.len});
    try w.writeAll("================================\n\n");
    for (typed.tables) |table| {
        try w.print("Table: {s}\n", .{table.name});
        try w.print("  Fields: {d}\n", .{table.columns.len});
        try w.print("  Indexes: {d}\n", .{table.indexes.len});
        try w.print("  Foreign Keys: {d}\n\n", .{table.fks.len});
    }
    return try aw.toOwnedSlice();
}

fn generateMarkdownExport(alloc: std.mem.Allocator, typed: anytype) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("# Schema Documentation\n\n");
    try w.writeAll("## Overview\n\n");
    try w.print("- **Tables**: {d}\n\n", .{typed.tables.len});
    try w.writeAll("## Tables\n\n");
    for (typed.tables) |table| {
        try w.print("### {s}\n\n", .{table.name});
        try w.writeAll("| Field | Type |\n");
        try w.writeAll("|-------|------|\n");
        for (table.columns) |col| {
            try w.print("| {s} | {s} |\n", .{ col.name, @tagName(col.sql_type) });
        }
        try w.writeByte('\n');
    }
    return try aw.toOwnedSlice();
}

// ─── JSON Helpers ────────────────────────────────────────────

fn writeJsonField(w: *Writer, key: []const u8, value: []const u8) !void {
    try writeJsonString(w, key);
    try w.writeAll(":");
    try writeJsonString(w, value);
}

fn writeJsonString(w: *Writer, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_export json" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_export(schema.ptr, schema.len, "format=json dialect=pg", 22);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "tables") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_export text" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_export(schema.ptr, schema.len, "format=text dialect=pg", 21);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "Schema:") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_export markdown" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_export(schema.ptr, schema.len, "format=markdown dialect=pg", 26);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "# Schema Documentation") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_export defaults to json" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_export(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(std.mem.indexOf(u8, output, "tables") != null);
    }
    @import("error.zig").rune_reset();
}
