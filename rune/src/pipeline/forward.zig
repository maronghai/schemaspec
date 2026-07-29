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
const json_schema = @import("../json_schema.zig");
const import_res = @import("import_resolver.zig");

// ─── Forward Pipeline: .ss → SQL ─────────────────────────────
// No dependency on cli.zig — output format dispatch is the caller's responsibility.

/// Intermediate results from the compilation pipeline.
/// Returned by compilePipeline so trace mode can inspect each stage
/// without re-running the pipeline.
pub const PipelineResult = struct {
    resolved: resolved_ast.ResolvedAst,
    lines: []tokenizer.Line,
    tree: ast_mod.Ast,
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
fn compileInternal(
    io: ?std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    import_ctx: ?*ImportContext,
    flags: CompileFlags,
) !struct { tree: ast_mod.Ast, lines: []tokenizer.Line, resolved: ?resolved_ast.ResolvedAst } {
    const raw_lines = try import_res.splitLines(alloc, file_data);

    // Resolve @import directives only when enabled and io is available
    const imports_result = if (flags.resolve_imports and import_ctx != null and io != null)
        try import_res.resolveImports(io.?, alloc, raw_lines, import_ctx.?)
    else
        null;

    // Use processed lines (with imports stripped) or raw lines
    const final_lines = if (imports_result) |r| r.processed_lines else raw_lines;

    // Tokenize and parse
    const result = try import_res.tokenizeAndParseWithLines(alloc, final_lines, flags.json_errors);

    // Merge imported definitions if requested
    var tree = result.tree;
    if (imports_result) |imports| {
        if (imports.templates.len > 0 or imports.tables.len > 0) {
            tree = .{
                .schema = tree.schema,
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
    const resolved = if (flags.run_semantic) blk: {
        var sa = if (flags.verbose_passes) semantic.SemanticAnalyzer.initVerbose(alloc) else semantic.SemanticAnalyzer.init(alloc);
        break :blk sa.analyze(tree) catch |err| return err;
    } else null;

    return .{ .tree = tree, .lines = result.tokenized, .resolved = resolved };
}

/// Shared tokenizer → parser → semantic pipeline.
/// Returns PipelineResult with all intermediate IRs for trace inspection.
pub fn compilePipeline(alloc: std.mem.Allocator, file_data: []const u8) !PipelineResult {
    const result = try compileInternal(null, alloc, file_data, null, .{});
    return .{ .resolved = result.resolved orelse return error.SemanticError, .lines = result.lines, .tree = result.tree };
}

/// Shared tokenizer → parser → semantic pipeline with verbose pass tracking.
pub fn compilePipelineVerbose(alloc: std.mem.Allocator, file_data: []const u8, verbose: bool, json_errors: bool) !PipelineResult {
    const result = try compileInternal(null, alloc, file_data, null, .{ .verbose_passes = verbose, .json_errors = json_errors });
    return .{ .resolved = result.resolved orelse return error.SemanticError, .lines = result.lines, .tree = result.tree };
}

/// Compile pipeline with import resolution. Handles @import directives by
/// recursively compiling imported files and merging their templates/tables.
fn compilePipelineWithImports(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext, json_errors: bool) !PipelineResult {
    const result = try compileInternal(io, alloc, file_data, import_ctx, .{
        .resolve_imports = true,
        .merge_imports = true,
        .json_errors = json_errors,
    });
    return .{ .resolved = result.resolved orelse return error.SemanticError, .lines = result.lines, .tree = result.tree };
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

// ─── Stats ──────────────────────────────────────────────────────

/// Compilation statistics.
pub const Stats = struct {
    tables: usize,
    fields: usize,
    views: usize,
};

/// Compute stats from a ResolvedAst.
pub fn computeStats(resolved: resolved_ast.ResolvedAst) Stats {
    var field_count: usize = 0;
    for (resolved.tables) |table| {
        field_count += table.fields.len;
    }
    return .{
        .tables = resolved.tables.len,
        .fields = field_count,
        .views = resolved.views.len,
    };
}

/// Print stats to stderr.
pub fn printStats(stats: Stats) void {
    std.debug.print("tables: {d}  fields: {d}  views: {d}\n", .{
        stats.tables, stats.fields, stats.views,
    });
}

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

    if (cfg.check) {
        if (!cfg.quiet) {
            std.debug.print("schema is valid\n", .{});
        }
        return;
    }

    try io_mod.writeOutput(io, output, cfg.output_path, cfg.quiet);
}

/// Validate a .ss file — runs the full semantic pipeline and reports diagnostics.
/// Always succeeds (exit 0) as long as the pipeline runs. Warnings and errors
/// are printed but do not cause a non-zero exit. Use `handleCheck` for CI gates.
pub fn handleValidate(_: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool) !void {
    const result = compilePipelineVerbose(alloc, file_data, verbose_passes, json_errors) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            // Diagnostics already printed by the compiler — validate always succeeds
            if (stats) {
                // Can't compute stats on failed compile, skip
            }
            return;
        }
        return err;
    };
    if (stats) {
        printStats(computeStats(result.resolved));
    }
    std.debug.print("schema is valid\n", .{});
}

/// Check a .ss file — runs the full semantic pipeline and fails on errors.
/// Returns error.DiagnosticsError or error.SemanticError on errors (exit code 1).
/// Used for CI gates: `rune check schema.ss` exits 1 if the schema has errors.
pub fn handleCheck(_: std.Io, alloc: std.mem.Allocator, file_data: []const u8, stats: bool, verbose_passes: bool, json_errors: bool) !void {
    const result = try compilePipelineVerbose(alloc, file_data, verbose_passes, json_errors);
    if (stats) {
        printStats(computeStats(result.resolved));
    }
    std.debug.print("schema is valid\n", .{});
}
