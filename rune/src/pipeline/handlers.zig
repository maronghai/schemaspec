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

// ─── Output Handlers ───────────────────────────────────────────
// CLI-level handlers that orchestrate compilation + output.
// Extracted from forward.zig for single-responsibility.

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
        std.debug.print("warning: schema has parse errors — {d} table(s) skipped, emitting SQL for valid tables only\n", .{pipeline.skipped_tables});
    }

    if (cfg.check) {
        if (pipeline.partial) {
            if (!cfg.quiet) {
                std.debug.print("schema has errors (partial output)\n", .{});
            }
            return error.DiagnosticsError;
        }
        if (!cfg.quiet) {
            std.debug.print("schema is valid\n", .{});
        }
        return;
    }

    try io_mod.writeOutput(io, output, cfg.output_path, cfg.quiet);
}

/// Validate a .ss file — runs the full semantic pipeline and reports diagnostics.
/// With strict=false (default validate): always succeeds (exit 0), prints errors but doesn't fail.
/// With strict=true (check mode): returns error.DiagnosticsError on errors (exit 1).
/// With json_errors=true: outputs JSON result instead of text.
pub fn handleValidate(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool, strict: bool) !void {
    const result = compilePipeline(alloc, file_data, .{ .verbose_passes = verbose_passes, .json_errors = json_errors }) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            if (json_errors) {
                const s = Stats{ .tables = 0, .fields = 0, .views = 0, .not_null_fields = 0, .numeric_fields = 0, .string_fields = 0, .datetime_fields = 0, .boolean_fields = 0, .other_fields = 0, .foreign_keys = 0, .indexes = 0, .check_constraints = 0, .custom_types = 0 };
                const json = try formatValidateResult(alloc, false, s, 1);
                try io_mod.writeOutput(io, json, null, false);
            } else {
                std.debug.print("schema has errors\n", .{});
            }
            if (strict) return err;
            return;
        }
        return err;
    };
    const s = computeStats(result.resolved);
    if (json_errors) {
        const json = try formatValidateResult(alloc, !result.partial, s, if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0);
        try io_mod.writeOutput(io, json, null, false);
    } else {
        if (stats) {
            printStats(s);
        }
        if (result.partial) {
            std.debug.print("schema has errors (partial)\n", .{});
            if (strict) return error.DiagnosticsError;
            return;
        }
        std.debug.print("schema is valid\n", .{});
    }
}

/// Check a .ss file — CI gate mode. Fails on any schema error.
pub fn handleCheck(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool) !void {
    return handleValidate(io, alloc, file_data, stats, verbose_passes, json_errors, true);
}

/// Stats a .ss file — runs the full semantic pipeline and prints table/field/view counts.
pub fn handleStats(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, format: StatsFormat) !void {
    const result = try compilePipeline(alloc, file_data, .{});
    const s = computeStats(result.resolved);
    switch (format) {
        .json => {
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

/// Format validate/check result as JSON.
pub fn formatValidateResult(alloc: std.mem.Allocator, valid: bool, s: Stats, error_count: u32) ![]const u8 {
    return std.fmt.allocPrint(alloc,
        \\{{"valid":{},"errors":{d},"tables":{d},"fields":{d},"views":{d}}}
    , .{
        valid,
        error_count,
        s.tables,
        s.fields,
        s.views,
    });
}

/// Compile a schema and run a named generator on it. Handles the full pipeline:
/// read input → compile → resolve types → lookup generator → generate → write output.
/// Used by both `rune generate <name>` and `rune docs` (which delegates to the "docs" generator).
pub fn generateFromSchema(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generator_name: []const u8,
    dialect: codegen.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
) !void {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);

    const generator = @import("../generator.zig");
    if (generator.get(generator_name)) |gen| {
        const output_text = try gen.generate(alloc, typed, dialect);
        try io_mod.writeOutput(io, output_text, output_path, quiet);
    } else {
        return error.UnknownGenerator;
    }
}

/// Batch generation: run multiple generators from a single compilation.
/// `generators_str` is a comma-separated list of generator names (e.g. "prisma,drizzle,openapi").
/// Each generator's output is written to a separate file: `<output_dir>/<generator_name>.<ext>`.
/// When output_path is null, outputs are written to stdout separated by headers.
pub fn generateFromSchemaBatch(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generators_str: []const u8,
    dialect: codegen.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
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
