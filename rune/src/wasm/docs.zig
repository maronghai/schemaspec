const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const common = @import("common.zig");
const Writer = std.Io.Writer;

// ─── WASM Docs Exports ────────────────────────────────────────
// Generate Markdown documentation for a schema.

/// Generate Markdown documentation via WASM.
/// Options: "dialect=<dialect>".
pub export fn rune_docs(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);

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

    // Generate documentation
    const output = generateDocs(alloc, typed) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

fn generateDocs(alloc: std.mem.Allocator, typed: anytype) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("# Schema Documentation\n\n");
    try w.writeAll("## Overview\n\n");
    try w.print("- **Tables**: {d}\n", .{typed.tables.len});

    // Count total fields
    var total_fields: usize = 0;
    for (typed.tables) |table| {
        total_fields += table.columns.len;
    }
    try w.print("- **Total Fields**: {d}\n\n", .{total_fields});

    // Table of contents
    try w.writeAll("## Table of Contents\n\n");
    for (typed.tables) |table| {
        try w.print("- [{s}](#{s})\n", .{ table.name, table.name });
    }
    try w.writeByte('\n');

    // Table details
    try w.writeAll("## Tables\n\n");
    for (typed.tables) |table| {
        try w.print("### {s}\n\n", .{table.name});

        // Fields table
        try w.writeAll("| Field | Type | Nullable | Default |\n");
        try w.writeAll("|-------|------|----------|--------|\n");
        for (table.columns) |col| {
            try w.print("| {s} | {s} | {s} | {s} |\n", .{
                col.name,
                @tagName(col.sql_type),
                if (col.flags.nullable) "yes" else "no",
                if (col.default) |d| d else "-",
            });
        }
        try w.writeByte('\n');

        // Indexes
        if (table.indexes.len > 0) {
            try w.writeAll("**Indexes:**\n\n");
            for (table.indexes) |idx| {
                try w.print("- `{s}`\n", .{idx.name});
            }
            try w.writeByte('\n');
        }

        // Foreign Keys
        if (table.fks.len > 0) {
            try w.writeAll("**Foreign Keys:**\n\n");
            for (table.fks) |fk| {
                try w.print("- {s} → `{s}`\n", .{ fk.fields[0], fk.ref_table });
            }
            try w.writeByte('\n');
        }
    }

    return try aw.toOwnedSlice();
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_docs basic" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_docs(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "# Schema Documentation") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "users") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_docs with multiple tables" {
    const schema =
        \\# users
        \\id N ++
        \\name s
        \\
        \\# posts
        \\id N ++
        \\title s128
        \\user_id N -> users.id
    ;
    const result = rune_docs(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "users") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "posts") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_docs with invalid schema" {
    const schema = "this is not valid";
    const result = rune_docs(schema.ptr, schema.len, "dialect=pg", 10);
    // Parser produces partial AST with warnings, not an error
    // So result may be non-null with empty tables
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
    }
    @import("error.zig").rune_reset();
}
