const std = @import("std");
const tokenizer = @import("../parser/tokenizer.zig");
const parser = @import("../parser/parser.zig");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const semantic = @import("../semantic/analyzer.zig");
const codegen = @import("../codegen/codegen.zig");
const typed_ast = @import("../types/typed_ast.zig");
const import_res = @import("import_resolver.zig");
const stats_mod = @import("stats.zig");
const fmt = @import("../diagnostic/format.zig");

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

/// Output format type.
pub const OutputFormat = enum {
    sql,
    json_schema,
};

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
    /// Use parallel streaming compilation (compile independent tables concurrently).
    parallel: bool = false,
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

/// Result of internal compilation pipeline.
/// Named struct for clarity instead of anonymous struct.
const CompileInternalResult = struct {
    tree: ast_mod.Ast,
    lines: []tokenizer.Line,
    resolved: ?resolved_ast.ResolvedAst,
    partial: bool,
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
) !CompileInternalResult {
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
        sa.dialect = cfg.dialect;
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

/// Compile in-memory SQL text to ResolvedAst via reverse engineering.
/// Used by `rune diff --from-sql` to avoid writing a temp file.
/// The SQL text is parsed, reverse-engineered to .ss, then compiled through the forward pipeline.
pub fn compileSqlToAst(alloc: std.mem.Allocator, sql_text: []const u8, dialect: codegen.Dialect) !resolved_ast.ResolvedAst {
    const sql_parser = @import("../parser/sql_parser.zig");
    const reverse_codegen_mod = @import("../reverse/codegen.zig");
    const dialect_detect_mod = @import("../reverse/dialect_detect.zig");

    // Auto-detect dialect from SQL content when using default MySQL
    const sql_dialect: sql_parser.Dialect = if (dialect == .mysql) dialect_detect_mod.detectSqlDialect(sql_text) else dialect;

    // Parse SQL → SqlSchema
    var sp_parser = try sql_parser.SqlParser.init(alloc, sql_text, sql_dialect);
    const parse_result = sp_parser.parse() catch {
        fmt.printError("sql-parse", "SQL parse error");
        return error.SqlParseError;
    };

    // Reverse-engineer SqlSchema → .ss text
    var rcg = reverse_codegen_mod.ReverseCodegen.init(alloc, sql_dialect);
    const ss_text = try rcg.generate(parse_result.schema);

    // Compile .ss text through the forward pipeline
    const pipeline = try compilePipeline(alloc, ss_text, .{});
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

/// Trace all stages — public wrapper for handlers.zig.
pub fn traceAll(pipeline: PipelineResult, typed: typed_ast.TypedAst) void {
    traceWithTyped(pipeline, typed);
}

// ─── Stats (re-exported from stats.zig) ──────────────────────────

pub const Stats = stats_mod.Stats;
pub const computeStats = stats_mod.computeStats;
pub const printStats = stats_mod.printStats;
