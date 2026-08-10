const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const dialect_mod = @import("../dialect/dialect.zig");
const diff_engine = @import("../diff/engine.zig");
const text_fmt = @import("../diff/format/text.zig");
const format_common = @import("../diff/format_common.zig");
const json_fmt = @import("../diff/format/json.zig");
const sarif_fmt = @import("../diff/format/sarif.zig");
const markdown_fmt = @import("../diff/format/markdown.zig");
const migrate = @import("../diff/migrate.zig");
const common = @import("common.zig");

// ─── WASM Diff Exports ──────────────────────────────────────────
// Diff and migration functions.

/// Format diff as text with summary statistics. Helper for rune_diff.
fn formatDiffText(alloc: std.mem.Allocator, d: diff_engine.SchemaDiff, dialect: @import("../dialect/enum.zig").Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = dialect_mod.getBackend(dialect).quoteChar;
    try text_fmt.writeDiffTo(w, d, q, false);
    // Add summary statistics
    const stats = format_common.DiffStats.compute(d);
    const total = stats.dropped_tables + stats.added_tables + stats.modified_tables;
    if (total > 0) {
        try w.writeAll("\n");
        try format_common.formatSummaryStats(w, stats, false);
    }
    try w.flush();
    return try aw.toOwnedSlice();
}

/// Compile two schemas and return the diff as text.
pub export fn rune_diff(schema1_ptr: [*]const u8, schema1_len: usize, schema2_ptr: [*]const u8, schema2_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema1 = schema1_ptr[0..schema1_len];
    const schema2 = schema2_ptr[0..schema2_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const fmt_type = common.parseDiffFormatOption(options);

    // Compile both schemas
    const old_result = pipeline.compilePipeline(alloc, schema1, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };
    const new_result = pipeline.compilePipeline(alloc, schema2, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Compute diff
    const schema_diff = diff_engine.diff(old_result.resolved, new_result.resolved, alloc) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Format diff based on requested format
    const output = switch (fmt_type) {
        .text => formatDiffText(alloc, schema_diff, dialect) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        },
        .json => json_fmt.formatDiffJson(alloc, schema_diff) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        },
        .sarif => sarif_fmt.formatDiffSarif(alloc, schema_diff, dialect) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        },
        .markdown => markdown_fmt.formatDiffMarkdown(alloc, schema_diff, dialect) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        },
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Compile two schemas and return migration SQL.
pub export fn rune_migrate(schema1_ptr: [*]const u8, schema1_len: usize, schema2_ptr: [*]const u8, schema2_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema1 = schema1_ptr[0..schema1_len];
    const schema2 = schema2_ptr[0..schema2_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const rollback = common.parseOption(options, "rollback") != null;

    // Compile both schemas
    const old_result = pipeline.compilePipeline(alloc, schema1, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };
    const new_result = pipeline.compilePipeline(alloc, schema2, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Compute diff
    const schema_diff = diff_engine.diff(old_result.resolved, new_result.resolved, alloc) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types for migration generation
    const new_typed = TypeResolver.resolve(alloc, new_result.resolved, dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Generate migration SQL
    const output = if (rollback)
        migrate.generateRollback(alloc, schema_diff, new_typed, new_result.resolved, dialect) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        }
    else
        migrate.generateFromDiff(alloc, schema_diff, new_typed, new_result.resolved, dialect) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_diff two schemas" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_diff json format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=json", 22);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, json, "{") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_diff sarif format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=sarif", 23);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_diff markdown format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=markdown", 26);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_migrate basic" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_migrate(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
    }
    @import("error.zig").rune_reset();
}

test "rune_migrate with rollback" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_migrate(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg rollback", 14);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
    }
    @import("error.zig").rune_reset();
}
