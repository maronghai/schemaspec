const std = @import("std");
const forward = @import("forward.zig");
const CompileConfig = forward.CompileConfig;
pub const OutputFormat = forward.OutputFormat;
const compilePipeline = forward.compilePipeline;
const compileFileWithPaths = forward.compileFileWithPaths;
const Stats = forward.Stats;
const computeStats = forward.computeStats;
const printStats = forward.printStats;
const io_mod = @import("../io.zig");
const codegen = @import("../codegen/codegen.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const json_schema = @import("../generators/json_schema.zig");
const generator = @import("../generator.zig");
const stats_mod = @import("stats.zig");
const StatsFormat = @import("../types/enums.zig").StatsFormat;
const fmt = @import("../diagnostic/format.zig");
const export_mod = @import("export.zig");
pub const ExportFormat = export_mod.ExportFormat;
pub const formatValidateResult = export_mod.formatValidateResult;
pub const formatValidateSarif = export_mod.formatValidateSarif;

// ─── Output Handlers ───────────────────────────────────────────
// CLI-level handlers that orchestrate compilation + output.
// Extracted from forward.zig for single-responsibility.

/// Compile schema text to a TypedAst for use by generators.
/// Single entry point for the compile → resolve pattern used by
/// generateFromSchema, generateFromSchemaBatch, and handleDocs.
pub fn compileToTypedAst(alloc: std.mem.Allocator, file_data: []const u8, dialect: codegen.Dialect) !TypedAst {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    return TypeResolver.resolve(alloc, pipeline.resolved, dialect);
}

/// Configuration for `handleValidate` and `handleCheck`.
/// Replaces 9 positional parameters with a named struct.
pub const ValidateConfig = struct {
    stats: bool = false,
    verbose_passes: bool = false,
    json_errors: bool = false,
    strict: bool = false,
    format: StatsFormat = .text,
    per_table: bool = false,
};

/// Configuration for `generateFromSchema` and `generateFromSchemaBatch`.
/// Replaces 8 positional parameters with a named struct.
pub const GenerateConfig = struct {
    /// Generator name (for single generation) or comma-separated list (for batch).
    generators: []const u8,
    /// Output file path or directory for batch mode. null = stdout.
    output: ?[]const u8 = null,
    /// Target dialect for dialect-specific output.
    dialect: codegen.Dialect = .mysql,
    /// Suppress non-error output.
    quiet: bool = false,
    /// Preview output without writing to files.
    dry_run: bool = false,
    /// List available generators and exit.
    list: bool = false,
    /// Run generator health check and exit.
    check: bool = false,
};

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

/// Validate a .ss file — runs the full semantic pipeline and reports diagnostics.
/// With strict=false (default validate): always succeeds (exit 0), prints errors but doesn't fail.
/// With strict=true (check mode): returns error.DiagnosticsError on errors (exit 1).
/// With json_errors=true or format=.json: outputs JSON result instead of text.
/// With format=.sarif: outputs SARIF result for CI/CD integration.
pub fn handleValidate(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ValidateConfig) !void {
    const result = compilePipeline(alloc, file_data, .{ .verbose_passes = cfg.verbose_passes, .json_errors = cfg.json_errors }) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            if (cfg.json_errors or cfg.format == .json) {
                const json = try formatValidateResult(alloc, false, Stats.zero, 1);
                try io_mod.writeOutput(io, json, null, false);
            } else if (cfg.format == .sarif) {
                const sarif = try formatValidateSarif(alloc, false, 1);
                try io_mod.writeOutput(io, sarif, null, false);
            } else {
                fmt.printError("schema", "has errors");
            }
            if (cfg.strict) return err;
            return;
        }
        return err;
    };
    const s = computeStats(result.resolved);
    if (cfg.json_errors or cfg.format == .json) {
        const json = try formatValidateResult(alloc, !result.partial, s, if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0);
        try io_mod.writeOutput(io, json, null, false);
    } else if (cfg.format == .sarif) {
        const error_count: u32 = if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0;
        const sarif = try formatValidateSarif(alloc, !result.partial, error_count);
        try io_mod.writeOutput(io, sarif, null, false);
    } else {
        if (cfg.stats or cfg.per_table) {
            printStats(s);
        }
        if (cfg.per_table) {
            const table_stats = stats_mod.computePerTableStats(result.resolved);
            stats_mod.printPerTableStats(table_stats);
        }
        if (result.partial) {
            fmt.printError("schema", "has errors (partial)");
            if (cfg.strict) return error.DiagnosticsError;
            return;
        }
        fmt.printOk("schema is valid");
    }
}

/// Check a .ss file — CI gate mode. Fails on any schema error.
pub fn handleCheck(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ValidateConfig) !void {
    return handleValidate(io, alloc, file_data, .{ .stats = cfg.stats, .verbose_passes = cfg.verbose_passes, .json_errors = cfg.json_errors, .strict = true, .format = cfg.format, .per_table = false });
}

/// Stats a .ss file — runs the full semantic pipeline and prints table/field/view counts.
pub fn handleStats(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: StatsConfig) !void {
    const result = try compilePipeline(alloc, file_data, .{});
    const s = computeStats(result.resolved);

    if (cfg.per_table) {
        const table_stats = stats_mod.computePerTableStats(result.resolved);
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
            const summary = try stats_mod.formatSummary(s);
            try io_mod.writeOutput(io, summary, null, false);
        },
    }
}

/// Compile a schema and run a named generator on it. Handles the full pipeline:
/// read input → compile → resolve types → lookup generator → generate → write output.
/// Used by both `rune generate <name>` and `rune docs` (which delegates to the "docs" generator).
/// When dry_run is true, output is written to stdout instead of the output file.
pub fn generateFromSchema(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generator_name: []const u8,
    dialect: codegen.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
    dry_run: bool,
) !void {
    const typed = try compileToTypedAst(alloc, file_data, dialect);

    if (generator.get(generator_name)) |gen| {
        const output_text = try gen.generate(alloc, typed, dialect);
        if (dry_run) {
            // Dry run: output to stdout without writing to file
            try io_mod.writeOutput(io, output_text, null, quiet);
        } else {
            try io_mod.writeOutput(io, output_text, output_path, quiet);
        }
    } else {
        return error.UnknownGenerator;
    }
}

/// Batch generation: run multiple generators from a single compilation.
/// `generators_str` is a comma-separated list of generator names (e.g. "prisma,drizzle,openapi").
/// Each generator's output is written to a separate file: `<output_dir>/<generator_name>.<ext>`.
/// When output_path is null, outputs are written to stdout separated by headers.
/// When dry_run is true, all outputs are written to stdout instead of files.
pub fn generateFromSchemaBatch(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generators_str: []const u8,
    dialect: codegen.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
    dry_run: bool,
) !void {
    const typed = try compileToTypedAst(alloc, file_data, dialect);

    // Split comma-separated generator names
    var gen_names = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    defer gen_names.deinit(alloc);

    var start: usize = 0;
    for (generators_str, 0..) |ch, i| {
        if (ch == ',' or i == generators_str.len - 1) {
            const end = if (ch == ',') i else i + 1;
            const name = std.mem.trim(u8, generators_str[start..end], " ");
            if (name.len > 0) {
                if (generator.get(name) == null) {
                    return error.UnknownGenerator;
                }
                try gen_names.append(alloc, name);
            }
            start = i + 1;
        }
    }

    if (gen_names.items.len == 0) {
        return error.UnknownGenerator;
    }

    // Generate each output
    for (gen_names.items) |gen_name| {
        if (generator.get(gen_name)) |gen| {
            const output_text = try gen.generate(alloc, typed, dialect);

            if (dry_run) {
                // Dry run: output to stdout with header
                if (!quiet) {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "--- {s} ---\n", .{gen_name}), null, quiet);
                }
                try io_mod.writeOutput(io, output_text, null, quiet);
            } else {
                // Determine output path
                const file_out = if (output_path) |base_path| blk: {
                    // Write to <base_path>/<generator_name><extension>
                    break :blk try std.fmt.allocPrint(alloc, "{s}/{s}{s}", .{ base_path, gen_name, gen.extension });
                } else null;

                if (file_out) |path| {
                    // Write to file
                    try std.Io.Dir.cwd().writeFile(io, .{
                        .sub_path = path,
                        .data = output_text,
                    });
                    if (!quiet) {
                        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Written to {s}\n", .{path}), null, quiet);
                    }
                } else {
                    // Write to stdout with header
                    if (!quiet) {
                        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "--- {s} ---\n", .{gen_name}), null, quiet);
                    }
                    try io_mod.writeOutput(io, output_text, null, quiet);
                }
            }
        }
    }
}

/// Unified generate handler using GenerateConfig struct.
/// Handles list, check, and generation modes.
pub fn handleGenerate(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: ?[]const u8,
    cfg: GenerateConfig,
) !void {
    if (cfg.list) {
        generator.listDetailedStderr();
        return;
    }
    if (cfg.check) {
        if (generator.check(alloc)) |err_msg| {
            try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Generator health check failed: {s}\n", .{err_msg}), null, false);
            std.process.exit(1);
        } else {
            try io_mod.writeOutput(io, "All generators OK\n", null, false);
        }
        return;
    }
    const data = file_data orelse return error.NoInput;
    const is_batch = std.mem.indexOf(u8, cfg.generators, ",") != null;
    if (is_batch) {
        try generateFromSchemaBatch(io, alloc, data, cfg.generators, cfg.dialect, cfg.output, cfg.quiet, cfg.dry_run);
    } else {
        try generateFromSchema(io, alloc, data, cfg.generators, cfg.dialect, cfg.output, cfg.quiet, cfg.dry_run);
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
    const formatted = try formatter.format(alloc, file_data);
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
