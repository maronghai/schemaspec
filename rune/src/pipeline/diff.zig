const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const pipeline_forward = @import("../pipeline/forward.zig");
const io_mod = @import("../io.zig");
const enums = @import("../types/enums.zig");

// ─── Diff Pipeline ────────────────────────────────────────────

/// Configuration for `rune diff` — replaces 8-9 positional parameters.
pub const DiffConfig = struct {
    old_path: []const u8,
    new_path: []const u8,
    dialect: dialect_enum.Dialect = .mysql,
    format: enums.DiffFormat = .text,
    output_path: ?[]const u8 = null,
    trace: bool = false,
    stats: bool = false,
    check: bool = false,
    color: enums.ColorMode = .auto,
    summary: bool = false,
    /// When set, compare old_path against this SQL file instead of new_path.
    /// Reverse-engineers the SQL file to .ss internally, then diffs.
    from_sql: ?[]const u8 = null,
};

/// Intermediate diff result shared by diff and migrate handlers.
pub const DiffResult = struct {
    old_ast: resolved_ast.ResolvedAst,
    new_ast: resolved_ast.ResolvedAst,
    schema_diff: diff_types.SchemaDiff,
};

/// Compile both schemas and compute their diff. Shared by all diff/migrate handlers.
pub fn prepareDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8) !DiffResult {
    const old_ast = try pipeline_forward.compileToAst(io, alloc, old_path);
    const new_ast = try pipeline_forward.compileToAst(io, alloc, new_path);
    const schema_diff = try diff.diff(old_ast, new_ast, alloc);
    return .{ .old_ast = old_ast, .new_ast = new_ast, .schema_diff = schema_diff };
}

/// Compile a .ss schema and diff it against a SQL dump file.
/// Reverse-engineers the SQL file to .ss internally, then compiles and diffs.
/// When sql_path is "-", reads SQL from stdin.
/// Uses in-memory compilation — no temp files.
fn prepareDiffFromSql(io: std.Io, alloc: std.mem.Allocator, ss_path: []const u8, sql_path: []const u8, dialect: dialect_enum.Dialect) !DiffResult {
    // 1. Compile the .ss file → old_resolved
    const old_ast = try pipeline_forward.compileToAst(io, alloc, ss_path);

    // 2. Read the SQL data (from file or stdin when sql_path is "-")
    const sql_data = try io_mod.readFileOrStdin(io, alloc, sql_path);

    // 3. Compile SQL text in-memory (reverse-engineer + forward pipeline)
    const new_ast = try pipeline_forward.compileSqlToAst(alloc, sql_data, dialect);

    // 4. Diff old_resolved vs new_resolved
    const schema_diff = try diff.diff(old_ast, new_ast, alloc);
    return .{ .old_ast = old_ast, .new_ast = new_ast, .schema_diff = schema_diff };
}

/// Handle `rune diff`: output schema differences between two .ss files.
/// Supports text, JSON, and SARIF output formats via DiffConfig.format.
/// With summary=true, outputs only the summary line without full diff.
/// With from_sql set, compares old_path against a SQL dump file instead of new_path.
pub fn handleDiff(io: std.Io, alloc: std.mem.Allocator, cfg: DiffConfig) !void {
    const result = if (cfg.from_sql) |sql_path|
        try prepareDiffFromSql(io, alloc, cfg.old_path, sql_path, cfg.dialect)
    else
        try prepareDiff(io, alloc, cfg.old_path, cfg.new_path);
    emitTraceAndStats(result, cfg.trace, cfg.stats);

    if (cfg.check) {
        if (result.schema_diff.hasChanges()) {
            // Text format writes the diff before failing (useful for CI output)
            if (cfg.format == .text) {
                const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, cfg.dialect, cfg.color, io);
                try io_mod.writeOutput(io, diff_text, null, false);
            }
            return error.CheckFailed;
        }
        return;
    }

    if (cfg.summary) {
        const summary_text = try diff_format.formatDiffSummary(alloc, result.schema_diff, cfg.color, io);
        try io_mod.writeOutput(io, summary_text, null, false);
        return;
    }

    switch (cfg.format) {
        .text => {
            const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, cfg.dialect, cfg.color, io);
            try io_mod.writeOutput(io, diff_text, null, false);
        },
        .json => {
            const json_text = try diff_format.formatDiffJson(alloc, result.schema_diff);
            try io_mod.writeOutput(io, json_text, cfg.output_path, false);
        },
        .sarif => {
            const sarif_text = try diff_format.formatDiffSarif(alloc, result.schema_diff, cfg.dialect);
            try io_mod.writeOutput(io, sarif_text, null, false);
        },
        .markdown => {
            const md_text = try diff_format.formatDiffMarkdown(alloc, result.schema_diff, cfg.dialect);
            try io_mod.writeOutput(io, md_text, cfg.output_path, false);
        },
    }
}

/// Emit trace and stats for a diff result — shared by diff and migrate handlers.
pub fn emitTraceAndStats(result: DiffResult, trace: bool, stats: bool) void {
    if (trace) traceDiffResult(result);
    if (stats) {
        const old_s = pipeline_forward.computeStats(result.old_ast);
        const new_s = pipeline_forward.computeStats(result.new_ast);
        std.debug.print("old: tables={d} fields={d} views={d}\n", .{ old_s.tables, old_s.fields, old_s.views });
        std.debug.print("new: tables={d} fields={d} views={d}\n", .{ new_s.tables, new_s.fields, new_s.views });
    }
}

// ─── Trace Helpers ──────────────────────────────────────────────

fn traceDiffResult(result: DiffResult) void {
    traceResolvedAst("old", result.old_ast);
    traceResolvedAst("new", result.new_ast);
    traceSchemaDiff(result.schema_diff);
}

fn traceResolvedAst(label: []const u8, ast: resolved_ast.ResolvedAst) void {
    std.debug.print("=== [{s} ResolvedAst] ===\n\n", .{label});
    std.debug.print("Schema: {?s}\n", .{ast.schema_name});
    std.debug.print("Tables ({d}):\n", .{ast.tables.len});
    for (ast.tables) |table| {
        std.debug.print("  # {s} ({d} fields, {d} fks, {d} indexes)\n", .{ table.name, table.fields.len, table.fks.len, table.indexes.len });
    }
    std.debug.print("\n", .{});
}

fn traceSchemaDiff(sd: diff_types.SchemaDiff) void {
    std.debug.print("=== [SchemaDiff] ===\n\n", .{});
    if (sd.dropped_tables.len > 0) {
        std.debug.print("Dropped tables ({d}):\n", .{sd.dropped_tables.len});
        for (sd.dropped_tables) |tname| {
            std.debug.print("  - {s}\n", .{tname});
        }
    }
    for (sd.table_diffs) |td| {
        std.debug.print("Table {s}: {s}\n", .{ td.name, @tagName(td.action) });
        for (td.field_diffs) |fd| {
            std.debug.print("  field {s}: {s}", .{ fd.name, @tagName(fd.action) });
            if (fd.rename_from) |rf| std.debug.print(" from {s}", .{rf});
            std.debug.print("\n", .{});
        }
        for (td.index_diffs) |idx| {
            std.debug.print("  index {s}: {s}\n", .{ idx.name, @tagName(idx.action) });
        }
    }
    std.debug.print("\n", .{});
}
