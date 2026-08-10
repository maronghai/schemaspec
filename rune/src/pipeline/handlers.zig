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
const json_schema = @import("../generators/json_schema.zig");
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
        std.debug.print("  {d} table(s) skipped, emitting SQL for valid tables only\n", .{pipeline.skipped_tables});
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
                const s = Stats{ .tables = 0, .fields = 0, .views = 0, .not_null_fields = 0, .numeric_fields = 0, .string_fields = 0, .datetime_fields = 0, .boolean_fields = 0, .other_fields = 0, .foreign_keys = 0, .indexes = 0, .check_constraints = 0, .custom_types = 0 };
                const json = try formatValidateResult(alloc, false, s, 1);
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
pub fn handleStats(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, format: StatsFormat, per_table: bool) !void {
    const result = try compilePipeline(alloc, file_data, .{});
    const s = computeStats(result.resolved);

    if (per_table) {
        const table_stats = stats_mod.computePerTableStats(result.resolved);
        switch (format) {
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

    switch (format) {
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
    const pipeline = try compilePipeline(alloc, file_data, .{});
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);

    const generator = @import("../generator.zig");
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
    const pipeline = try compilePipeline(alloc, file_data, .{});
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);

    const generator = @import("../generator.zig");

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
                    std.debug.print("--- {s} ---\n", .{gen_name});
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
                        std.debug.print("Written to {s}\n", .{path});
                    }
                } else {
                    // Write to stdout with header
                    if (!quiet) {
                        std.debug.print("--- {s} ---\n", .{gen_name});
                    }
                    try io_mod.writeOutput(io, output_text, null, quiet);
                }
            }
        }
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
    const pipeline = try compilePipeline(alloc, file_data, .{});
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);
    const docs_mod = @import("../generators/docs.zig");
    const fmt_enum: docs_mod.DocFormat = switch (doc_format) {
        .markdown => .markdown,
        .json => .json,
    };
    const output_text = try docs_mod.generateWithFormat(alloc, typed, fmt_enum);
    try io_mod.writeOutput(io, output_text, output_path, quiet);
}

pub const DocsFormat = enum { markdown, json };

/// Format a .ss file.
pub fn handleFormat(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    output_path: ?[]const u8,
    check: bool,
    quiet: bool,
) !void {
    const formatter = @import("../formatter.zig");
    const formatted = try formatter.format(alloc, file_data);
    if (check) {
        if (!std.mem.eql(u8, formatted, file_data)) {
            return error.FormatCheckFailed;
        }
        return;
    }
    try io_mod.writeOutput(io, formatted, output_path, quiet);
}

/// Export schema as structured data for tooling integration.
pub fn handleExport(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    output_path: ?[]const u8,
    export_format: ExportFormat,
    quiet: bool,
) !void {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    try export_mod.exportSchema(io, alloc, pipeline, output_path, export_format, quiet);
}
