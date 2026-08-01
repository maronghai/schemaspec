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

/// Flags controlling pipeline behavior.
const CompileFlags = struct {
    resolve_imports: bool = false,
    run_semantic: bool = true,
    merge_imports: bool = false,
    verbose_passes: bool = false,
    json_errors: bool = false,
};

/// Configuration for the compile handler — replaces 13 positional parameters.
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
};

/// Unified internal compilation pipeline.
/// Handles tokenize → parse → (optional imports) → (optional semantic) → ResolvedAst.
/// `io` is only used when `resolve_imports` is true; pass null when imports are disabled.
/// When parse errors exist, prints them and returns early.
/// When parsing succeeds but semantic errors exist, those are also printed.
/// All errors from both phases are visible to the user.
fn compileInternal(
    io: ?std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    import_ctx: ?*ImportContext,
    flags: CompileFlags,
) !struct { tree: ast_mod.Ast, lines: []tokenizer.Line, resolved: ?resolved_ast.ResolvedAst, partial: bool } {
    const raw_lines = try import_res.splitLines(alloc, file_data);

    // Resolve @import directives only when enabled and io is available
    const imports_result = if (flags.resolve_imports and import_ctx != null and io != null)
        try import_res.resolveImports(io.?, alloc, raw_lines, import_ctx.?)
    else
        null;

    // Use processed lines (with imports stripped) or raw lines
    const final_lines = if (imports_result) |r| r.processed_lines else raw_lines;

    // Tokenize and parse — returns error on parse errors (which are printed internally).
    // The tree is always valid; error_count indicates partial results.
    const result = try import_res.tokenizeAndParseWithLines(alloc, final_lines, flags.json_errors);

    // Merge imported definitions if requested
    var tree = result.tree;
    if (imports_result) |imports| {
        if (imports.templates.len > 0 or imports.tables.len > 0) {
            tree = .{
                .schema = tree.schema,
                .error_count = tree.error_count,
                .templates = try import_res.concatSlices(alloc, ast_mod.Template, tree.templates, imports.templates),
                .tables = try import_res.concatSlices(alloc, ast_mod.Table, tree.tables, imports.tables),
                .views = if (flags.merge_imports)
                    try import_res.concatSlices(alloc, ast_mod.View, tree.views, imports.views)
                else
                    tree.views,
                .sql_comments = if (flags.merge_imports)
                    try import_res.concatSlices(alloc, ast_mod.SqlComment, tree.sql_comments, imports.comments)
                else
                    tree.sql_comments,
            };
        }
    }

    // Run semantic analysis if requested
    // In partial mode (error_count > 0), still run semantic analysis on available tables.
    // Successfully parsed tables are complete; errored tables are simply absent.
    const resolved = if (flags.run_semantic) blk: {
        var sa = if (flags.verbose_passes) semantic.SemanticAnalyzer.initVerbose(alloc) else semantic.SemanticAnalyzer.init(alloc);
        break :blk sa.analyze(tree) catch |err| return err;
    } else null;

    return .{
        .tree = tree,
        .lines = result.tokenized,
        .resolved = resolved,
        .partial = tree.error_count > 0,
    };
}

/// Shared tokenizer → parser → semantic pipeline.
/// Returns PipelineResult with all intermediate IRs for trace inspection.
pub fn compilePipeline(alloc: std.mem.Allocator, file_data: []const u8) !PipelineResult {
    const result = try compileInternal(null, alloc, file_data, null, .{});
    return .{
        .resolved = result.resolved orelse return error.SemanticError,
        .lines = result.lines,
        .tree = result.tree,
        .partial = result.partial,
        .skipped_tables = if (result.partial) @intCast(result.tree.error_count) else 0,
    };
}

/// Shared tokenizer → parser → semantic pipeline with verbose pass tracking.
pub fn compilePipelineVerbose(alloc: std.mem.Allocator, file_data: []const u8, verbose: bool, json_errors: bool) !PipelineResult {
    const result = try compileInternal(null, alloc, file_data, null, .{ .verbose_passes = verbose, .json_errors = json_errors });
    return .{
        .resolved = result.resolved orelse return error.SemanticError,
        .lines = result.lines,
        .tree = result.tree,
        .partial = result.partial,
        .skipped_tables = if (result.partial) @intCast(result.tree.error_count) else 0,
    };
}

/// Compile pipeline with import resolution. Handles @import directives by
/// recursively compiling imported files and merging their templates/tables.
fn compilePipelineWithImports(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext, json_errors: bool) !PipelineResult {
    const result = try compileInternal(io, alloc, file_data, import_ctx, .{
        .resolve_imports = true,
        .merge_imports = true,
        .json_errors = json_errors,
    });
    return .{
        .resolved = result.resolved orelse return error.SemanticError,
        .lines = result.lines,
        .tree = result.tree,
        .partial = result.partial,
        .skipped_tables = if (result.partial) @intCast(result.tree.error_count) else 0,
    };
}

/// Tokenize and parse a .ss file, resolving @import directives recursively.
/// Used for importing templates and tables from other files.
fn parseOnly(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext) !ast_mod.Ast {
    const result = try compileInternal(io, alloc, file_data, import_ctx, .{
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

    return compilePipelineWithImports(io, alloc, file_data, &ctx, json_errors);
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
        try compilePipelineVerbose(alloc, try io_mod.readStdin(io, alloc), cfg.verbose_passes, cfg.json_errors);

    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, cfg.dialect);

    const output = switch (cfg.format) {
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
pub fn handleValidate(_: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool, strict: bool) !void {
    const result = compilePipelineVerbose(alloc, file_data, verbose_passes, json_errors) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            std.debug.print("schema has errors\n", .{});
            if (strict) return err;
            return;
        }
        return err;
    };
    if (stats) {
        printStats(computeStats(result.resolved));
    }
    if (result.partial) {
        std.debug.print("schema has errors (partial)\n", .{});
        if (strict) return error.DiagnosticsError;
        return;
    }
    std.debug.print("schema is valid\n", .{});
}

/// Check a .ss file — CI gate mode. Fails on any schema error.
pub fn handleCheck(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool) !void {
    return handleValidate(io, alloc, file_data, stats, verbose_passes, json_errors, true);
}

/// Stats a .ss file — runs the full semantic pipeline and prints table/field/view counts.
pub fn handleStats(_: std.Io, alloc: std.mem.Allocator, file_data: []const u8) !void {
    const result = try compilePipelineVerbose(alloc, file_data, false, false);
    const s = computeStats(result.resolved);
    std.debug.print("tables:  {d}\n", .{s.tables});
    std.debug.print("fields:  {d}\n", .{s.fields});
    std.debug.print("views:   {d}\n", .{s.views});
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
    const pipeline = try compilePipeline(alloc, file_data);
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);

    const generator = @import("../generator.zig");
    if (generator.get(generator_name)) |gen| {
        const output_text = try gen.generate(alloc, typed, dialect);
        try io_mod.writeOutput(io, output_text, output_path, quiet);
    } else {
        std.debug.print("error: unknown generator '{s}'. Run 'rune generate --list' for available generators.\n", .{generator_name});
        std.process.exit(1);
    }
}
