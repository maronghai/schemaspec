const std = @import("std");
const tokenizer = @import("../parser/tokenizer.zig");
const parser = @import("../parser/parser.zig");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const semantic = @import("../semantic/analyzer.zig");
const codegen = @import("../codegen/codegen.zig");
const typed_ast = @import("../types/typed_ast.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const diag = @import("../semantic/diagnostic.zig");
const io_mod = @import("../io.zig");
const json_schema = @import("../generators/json_schema.zig");
const import_res = @import("import_resolver.zig");
const stats_mod = @import("stats.zig");

// ─── Forward Pipeline: .ss → SQL ─────────────────────────────
// No dependency on cli.zig — output format dispatch is the caller's responsibility.

/// Intermediate results from the compilation pipeline.
/// Returned by compilePipeline so trace mode can inspect each stage
/// without re-running the pipeline.
pub const PipelineResult = struct {
    resolved: resolved_ast.ResolvedAst,
    lines: []tokenizer.Line,
    tree: ast_mod.Ast,
    /// True when some tables were skipped due to parse errors (partial compilation).
    partial: bool = false,
    /// Number of tables skipped during partial compilation.
    skipped_tables: u32 = 0,
};

// ─── Re-export import types for callers ────────────────────────
pub const ImportContext = import_res.ImportContext;
pub const ImportSet = import_res.ImportSet;
pub const ImportCache = import_res.ImportCache;

// ─── Unified Pipeline ──────────────────────────────────────────

/// Configuration for the compile pipeline — replaces both the old `PipelineOptions` and
/// `CompileConfig` structs. All fields have safe defaults so callers only specify what they change.
pub const CompileConfig = struct {
    /// Input path. null = read from stdin, else file path.
    input: ?[]const u8 = null,
    /// Output path. null = stdout, else file path.
    output_path: ?[]const u8 = null,
    /// Print compilation trace (tokens, AST, passes).
    trace: bool = false,
    /// Target SQL dialect.
    dialect: codegen.Dialect = .mysql,
    /// Output format (SQL or JSON Schema).
    format: OutputFormat = .sql,
    /// Print compilation stats (table count, type distribution).
    stats: bool = false,
    /// Check mode: validate schema, exit 0 if valid, don't emit output.
    check: bool = false,
    /// Suppress non-error output (e.g. "schema is valid" message).
    quiet: bool = false,
    /// Run semantic passes in verbose mode (print each pass name and timing).
    verbose_passes: bool = false,
    /// Emit diagnostics in JSON format (for CI/CD integration).
    json_errors: bool = false,
    /// Additional search paths for @import resolution.
    import_paths: []const []const u8 = &.{},
    /// Use streaming compilation mode (emit each table's SQL independently).
    stream: bool = false,
    /// Enable ANSI color output for diagnostics.
    color: bool = false,
    /// I/O handle for file reading (required for import resolution).
    io: ?std.Io = null,
    /// Import context for @import resolution. Requires io != null.
    import_ctx: ?*ImportContext = null,
    /// Resolve @import directives recursively.
    resolve_imports: bool = false,
    /// Merge imported definitions into the main AST.
    merge_imports: bool = false,
    /// Run semantic analysis. Set to false for parse-only mode.
    run_semantic: bool = true,
};

/// Unified internal compilation pipeline.
/// Handles tokenize → parse → (optional imports) → (optional semantic) → ResolvedAst.
/// `io` is only used when `resolve_imports` is true; pass null when imports are disabled.
/// When parse errors exist, prints them and returns early.
/// When parsing succeeds but semantic errors exist, those are also printed.
/// All errors from both phases are visible to the user.
fn compileInternal(
    alloc: std.mem.Allocator,
    file_data: []const u8,
    cfg: CompileConfig,
) !struct { tree: ast_mod.Ast, lines: []tokenizer.Line, resolved: ?resolved_ast.ResolvedAst, partial: bool } {
    const raw_lines = try import_res.splitLines(alloc, file_data);

    // Resolve @import directives only when enabled and io is available
    const imports_result = if (cfg.resolve_imports and cfg.import_ctx != null and cfg.io != null)
        try import_res.resolveImports(cfg.io.?, alloc, raw_lines, cfg.import_ctx.?)
    else
        null;

    // Use processed lines (with imports stripped) or raw lines
    const final_lines = if (imports_result) |r| r.processed_lines else raw_lines;

    // Tokenize and parse — returns error on parse errors (which are printed internally).
    // The tree is always valid; error_count indicates partial results.
    const result = try import_res.tokenizeAndParseWithLines(alloc, final_lines, cfg.json_errors);

    // Merge imported definitions if requested
    var tree = result.tree;
    if (imports_result) |imports| {
        if (imports.templates.len > 0 or imports.tables.len > 0) {
            tree = .{
                .schema = tree.schema,
                .error_count = tree.error_count,
                .templates = try import_res.concatSlices(alloc, ast_mod.Template, tree.templates, imports.templates),
                .tables = try import_res.concatSlices(alloc, ast_mod.Table, tree.tables, imports.tables),
                .views = if (cfg.merge_imports)
                    try import_res.concatSlices(alloc, ast_mod.View, tree.views, imports.views)
                else
                    tree.views,
                .sql_comments = if (cfg.merge_imports)
                    try import_res.concatSlices(alloc, ast_mod.SqlComment, tree.sql_comments, imports.comments)
                else
                    tree.sql_comments,
            };
        }
    }

    // Run semantic analysis if requested
    // In partial mode (error_count > 0), still run semantic analysis on available tables.
    // Successfully parsed tables are complete; errored tables are simply absent.
    const resolved = if (cfg.run_semantic) blk: {
        var sa = semantic.SemanticAnalyzer.initWithColor(alloc, cfg.verbose_passes, cfg.color);
        break :blk try sa.analyze(tree);
    } else null;

    return .{
        .tree = tree,
        .lines = result.tokenized,
        .resolved = resolved,
        .partial = tree.error_count > 0,
    };
}

/// Shared tokenizer → parser → semantic pipeline.
/// Unified entry point replacing compilePipeline/compilePipelineVerbose/compilePipelineWithImports.
/// Returns PipelineResult with all intermediate IRs for trace inspection.
pub fn compilePipeline(alloc: std.mem.Allocator, file_data: []const u8, cfg: CompileConfig) !PipelineResult {
    const result = try compileInternal(alloc, file_data, cfg);
    return .{
        .resolved = result.resolved orelse return error.SemanticError,
        .lines = result.lines,
        .tree = result.tree,
        .partial = result.partial,
        .skipped_tables = if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0,
    };
}

/// Tokenize and parse a .ss file, resolving @import directives recursively.
/// Used for importing templates and tables from other files.
fn parseOnly(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext) !ast_mod.Ast {
    const result = try compileInternal(alloc, file_data, .{
        .io = io,
        .import_ctx = import_ctx,
        .resolve_imports = true,
        .run_semantic = false,
    });
    return result.tree;
}

// ─── Public API ────────────────────────────────────────────────

/// Compile a .ss file by path, handling @import directives.
pub fn compileFile(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, json_errors: bool) !PipelineResult {
    return compileFileWithPaths(io, alloc, file_path, &.{}, json_errors);
}

/// Compile a .ss file by path with additional import search paths.
pub fn compileFileWithPaths(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, import_paths: []const []const u8, json_errors: bool) !PipelineResult {
    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, file_path, alloc, .unlimited);
    const base_dir = import_res.computeBaseDir(alloc, file_path);

    var imported = ImportSet.init(alloc);
    defer imported.deinit();

    // Cache for memoizing parsed imports (avoids re-parsing the same file)
    var cache = ImportCache.init(alloc);
    defer cache.deinit();

    // Track the initial file to prevent self-import
    try imported.put(file_path, {});

    var ctx = ImportContext{
        .base_dir = base_dir,
        .imported = &imported,
        .cache = &cache,
        .import_paths = import_paths,
    };

    return compilePipeline(alloc, file_data, .{
        .io = io,
        .import_ctx = &ctx,
        .resolve_imports = true,
        .merge_imports = true,
        .json_errors = json_errors,
    });
}

/// Compile a .ss file path to ResolvedAst (used by diff/migrate pipelines).
pub fn compileToAst(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !resolved_ast.ResolvedAst {
    const pipeline = try compileFile(io, alloc, path, false);
    return pipeline.resolved;
}

// ─── Trace Helpers ─────────────────────────────────────────────

/// Trace all forward pipeline stages including TypedAst (for SQL output).
fn traceWithTyped(pipeline: PipelineResult, typed: typed_ast.TypedAst) void {
    tokenizer.Tokenizer.diagnosticTrace(pipeline.lines);
    parser.diagnosticTrace(pipeline.tree);
    semantic.diagnosticTrace(pipeline.resolved);
    codegen.diagnosticTrace(typed);
}

/// Trace forward pipeline stages only (for JSON Schema output, no TypedAst).
fn traceForward(pipeline: PipelineResult) void {
    tokenizer.Tokenizer.diagnosticTrace(pipeline.lines);
    parser.diagnosticTrace(pipeline.tree);
    semantic.diagnosticTrace(pipeline.resolved);
}

// ─── Stats (re-exported from stats.zig) ──────────────────────────

pub const Stats = stats_mod.Stats;
pub const computeStats = stats_mod.computeStats;
pub const printStats = stats_mod.printStats;

// ─── Output Handlers ───────────────────────────────────────────

/// Output format type.
pub const OutputFormat = enum {
    sql,
    json_schema,
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

    const output = if (cfg.stream and cfg.format == .sql) blk: {
        const streaming = @import("../codegen/streaming.zig");
        var pool = codegen.BufferPool.init(alloc);
        defer pool.deinit();
        var sc = streaming.StreamingCodegen.initWithPool(alloc, cfg.dialect, &pool);
        const result = try sc.generateStreaming(typed);
        break :blk try streaming.formatStreamingResult(alloc, &result, cfg.dialect);
    } else switch (cfg.format) {
        .sql => blk: {
            var cg = codegen.Codegen.init(alloc, cfg.dialect);
            break :blk try cg.generateFromTypedAst(typed);
        },
        .json_schema => blk: {
            break :blk try json_schema.generate(alloc, typed, cfg.dialect);
        },
    };

    if (cfg.trace) {
        if (cfg.format == .sql) traceWithTyped(pipeline, typed) else traceForward(pipeline);
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
pub fn handleStats(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, json_output: bool) !void {
    const result = try compilePipeline(alloc, file_data, .{});
    const s = computeStats(result.resolved);
    if (json_output) {
        const json = try stats_mod.formatStatsJson(alloc, s);
        try io_mod.writeOutput(io, json, null, false);
    } else {
        printStats(s);
    }
}

/// Format validate/check result as JSON.
fn formatValidateResult(alloc: std.mem.Allocator, valid: bool, s: Stats, error_count: u32) ![]const u8 {
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
