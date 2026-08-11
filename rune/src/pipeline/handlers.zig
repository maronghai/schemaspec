const std = @import("std");
const forward = @import("forward.zig");
const CompileConfig = forward.CompileConfig;
pub const OutputFormat = forward.OutputFormat;
const compilePipeline = forward.compilePipeline;
const compileFileWithPaths = forward.compileFileWithPaths;
const computeStats = forward.computeStats;
const printStats = forward.printStats;
const io_mod = @import("../io.zig");
const codegen = @import("../codegen/codegen.zig");
const dialect_enum = @import("../dialect/enum.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const json_schema = @import("../generators/json_schema.zig");
const stats_mod = @import("stats.zig");
const StatsFormat = @import("../types/enums.zig").StatsFormat;
const fmt = @import("../diagnostic/format.zig");
const export_mod = @import("export.zig");
const validation = @import("validation.zig");
pub const ValidateConfig = validation.ValidateConfig;
pub const handleValidate = validation.handleValidate;
pub const handleCheck = validation.handleCheck;
pub const ExportFormat = export_mod.ExportFormat;
pub const formatValidateResult = export_mod.formatValidateResult;
pub const formatValidateSarif = export_mod.formatValidateSarif;

// ─── Output Handlers ───────────────────────────────────────────
// CLI-level handlers that orchestrate compilation + output.
// Extracted from forward.zig for single-responsibility.
// Validation handlers (handleValidate, handleCheck) live in validation.zig.

/// Compile schema text to a TypedAst for use by generators.
/// Single entry point for the compile → resolve pattern used by
/// generateFromSchema, generateFromSchemaBatch, and handleDocs.
fn compileToTypedAst(alloc: std.mem.Allocator, file_data: []const u8, dialect: dialect_enum.Dialect) !TypedAst {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    return TypeResolver.resolve(alloc, pipeline.resolved, dialect);
}

/// Unified compile handler for all combinations of input (stdin/file) and output (sql/json).
pub fn handleCompileRequest(
    io: std.Io,
    alloc: std.mem.Allocator,
    cfg: CompileConfig,
) !void {
    const pipeline = if (cfg.input) |path|
        try compileFileWithPaths(io, alloc, path, cfg.import_paths, cfg.json_errors)
    else
        try compilePipeline(alloc, try io_mod.readStdin(io, alloc), .{
            .verbose_passes = cfg.verbose_passes,
            .json_errors = cfg.json_errors,
            .io = io,
            .dialect = cfg.dialect,
            .trace = cfg.trace,
            .stats = cfg.stats,
            .check = cfg.check,
            .quiet = cfg.quiet,
            .stream = cfg.stream,
            .color = cfg.color,
            .run_semantic = cfg.run_semantic,
        });

    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, cfg.dialect);

    const output = if (cfg.stream and cfg.parallel and cfg.format == .sql) blk: {
        const parallel_mod = @import("../codegen/parallel.zig");
        const result = try parallel_mod.compileParallel(alloc, cfg.dialect, typed, .{});
        break :blk try @import("../codegen/streaming.zig").formatStreamingResult(alloc, &result, cfg.dialect);
    } else if (cfg.stream and cfg.format == .sql) blk: {
        const streaming = @import("../codegen/streaming.zig");
        var pool = codegen.BufferPool.init(alloc);
        defer pool.deinit();
        var sc = try streaming.StreamingCodegen.initWithPool(alloc, cfg.dialect, &pool);
        const result = try sc.generateStreaming(typed);
        break :blk try streaming.formatStreamingResult(alloc, &result, cfg.dialect);
    } else switch (cfg.format) {
        .sql => blk: {
            var pool = codegen.BufferPool.init(alloc);
            defer pool.deinit();
            var cg = codegen.Codegen.init(alloc, cfg.dialect);
            const result = try cg.generateFromTypedAstPooled(&pool, typed);
            break :blk result.sql;
        },
        .json_schema => blk: {
            break :blk try json_schema.generate(alloc, typed, cfg.dialect);
        },
    };

    if (cfg.trace) {
        forward.traceAll(pipeline, typed);
    }

    if (cfg.stats) {
        printStats(computeStats(pipeline.resolved));
    }

    if (pipeline.partial and !cfg.quiet) {
        fmt.printWarn("schema has parse errors");
        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "  {d} table(s) skipped, emitting SQL for valid tables only\n", .{pipeline.skipped_tables}), null, cfg.quiet);
    }

    if (cfg.check) {
        if (pipeline.partial) {
            if (!cfg.quiet) {
                fmt.printError("schema", "has errors (partial output)");
            }
            return error.DiagnosticsError;
        }
        if (!cfg.quiet) {
            fmt.printOk("schema is valid");
        }
        return;
    }

    try io_mod.writeOutput(io, output, cfg.output_path, cfg.quiet);
}

/// Stats a .ss file — runs the full semantic pipeline and prints table/field/view counts.
pub fn handleStats(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: StatsConfig) !void {
    const result = try compilePipeline(alloc, file_data, .{});
    const s = computeStats(result.resolved);

    if (cfg.per_table) {
        const table_stats = stats_mod.computePerTableStats(alloc, result.resolved);
        switch (cfg.format) {
            .json, .sarif => {
                const json = try stats_mod.formatPerTableStatsJson(alloc, table_stats);
                try io_mod.writeOutput(io, json, null, false);
            },
            .markdown => {
                const md = try stats_mod.formatPerTableStatsMarkdown(alloc, table_stats);
                try io_mod.writeOutput(io, md, null, false);
            },
            .text, .summary => {
                stats_mod.printPerTableStats(table_stats);
            },
        }
        return;
    }

    switch (cfg.format) {
        .json, .sarif => {
            const json = try stats_mod.formatStatsJson(alloc, s);
            try io_mod.writeOutput(io, json, null, false);
        },
        .markdown => {
            const md = try stats_mod.formatStatsMarkdown(alloc, s);
            try io_mod.writeOutput(io, md, null, false);
        },
        .text => {
            printStats(s);
        },
        .summary => {
            const summary = try stats_mod.formatSummary(alloc, s);
            try io_mod.writeOutput(io, summary, null, false);
        },
    }
}

/// Generate documentation from a .ss schema file.
pub fn handleDocs(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    output_path: ?[]const u8,
    doc_format: DocsFormat,
    quiet: bool,
    dialect: @import("../dialect/enum.zig").Dialect,
) !void {
    const typed = try compileToTypedAst(alloc, file_data, dialect);
    const docs_mod = @import("../generators/docs.zig");
    const fmt_enum: docs_mod.DocFormat = switch (doc_format) {
        .markdown => .markdown,
        .json => .json,
    };
    const output_text = try docs_mod.generateWithFormat(alloc, typed, fmt_enum);
    try io_mod.writeOutput(io, output_text, output_path, quiet);
}

pub const DocsFormat = @import("../cli/types.zig").DocsFormat;

/// Configuration for `handleFormat`.
/// Replaces 7 positional parameters with a named struct.
pub const FormatConfig = struct {
    /// Output file path. null = stdout.
    output: ?[]const u8 = null,
    /// Check mode: return error if formatting would change the file.
    check: bool = false,
    /// Diff mode: show line-by-line differences.
    diff: bool = false,
    /// Suppress non-error output.
    quiet: bool = false,
    /// Write mode: format and write back to the input file in-place.
    write: bool = false,
    /// Target SQL dialect for dialect-aware keyword formatting.
    dialect: ?@import("../dialect/enum.zig").Dialect = null,
    /// Input file path (needed for --write to write back in-place).
    input_path: ?[]const u8 = null,
};

/// Configuration for `handleExport`.
/// Replaces 6 positional parameters with a named struct.
pub const ExportConfig = struct {
    /// Output file path. null = stdout.
    output: ?[]const u8 = null,
    /// Export format: json, text, or markdown.
    format: ExportFormat = .json,
    /// Suppress non-error output.
    quiet: bool = false,
};

/// Configuration for `handleStats`.
/// Replaces 5 positional parameters with a named struct.
pub const StatsConfig = struct {
    /// Output format: text, json, sarif, markdown, or summary.
    format: StatsFormat = .text,
    /// Show per-table breakdown.
    per_table: bool = false,
};

/// Format a .ss file.
pub fn handleFormat(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    cfg: FormatConfig,
) !void {
    const formatter = @import("../formatter.zig");
    const formatted = try formatter.formatDialect(alloc, file_data, cfg.dialect);
    if (cfg.check) {
        if (!std.mem.eql(u8, formatted, file_data)) {
            if (!cfg.quiet) {
                fmt.printWarn("formatting needed");
            }
            return error.FormatCheckFailed;
        }
        return;
    }
    if (cfg.diff) {
        // Show line-by-line differences between original and formatted
        var original_lines = std.mem.splitScalar(u8, file_data, '\n');
        var formatted_lines = std.mem.splitScalar(u8, formatted, '\n');
        var line_no: usize = 1;
        var changed: usize = 0;
        while (true) {
            const orig = original_lines.next();
            const fmt_line = formatted_lines.next();
            if (orig == null and fmt_line == null) break;
            const o = orig orelse "";
            const f = fmt_line orelse "";
            if (!std.mem.eql(u8, o, f)) {
                changed += 1;
                if (!cfg.quiet) {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "- {d}: {s}\n", .{ line_no, o }), null, true);
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "+ {d}: {s}\n", .{ line_no, f }), null, true);
                }
            }
            line_no += 1;
        }
        if (changed > 0) {
            if (!cfg.quiet) {
                try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "\n{d} line(s) would change\n", .{changed}), null, true);
            }
            return error.FormatCheckFailed;
        }
        return;
    }
    if (cfg.write) {
        // --write with -o: write to specified output path
        // --write without -o: write back to the input file in-place
        const write_path = cfg.output orelse cfg.input_path;
        if (write_path) |path| {
            try io_mod.writeOutput(io, formatted, path, cfg.quiet);
        } else {
            if (!cfg.quiet) {
                fmt.printWarn("--write requires a file path (not stdin)");
            }
            return error.FormatWriteError;
        }
        return;
    }
    try io_mod.writeOutput(io, formatted, cfg.output, cfg.quiet);
}

/// Export schema as structured data for tooling integration.
pub fn handleExport(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    cfg: ExportConfig,
) !void {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    try export_mod.exportSchema(io, alloc, pipeline, cfg.output, cfg.format, cfg.quiet);
}
