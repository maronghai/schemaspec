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

// ─── Import Support ───────────────────────────────────────────

/// Set of imported file paths for circular dependency detection.
const ImportSet = std.StringHashMap(void);

/// Cached parse result for a previously imported file.
const CachedImport = struct {
    templates: []const ast_mod.Template,
    tables: []const ast_mod.Table,
    views: []const ast_mod.View,
    comments: []const ast_mod.SqlComment,
};

/// Cache of parsed import files — keyed by resolved path.
const ImportCache = std.StringHashMap(CachedImport);

/// Context for resolving @import directives during parsing.
pub const ImportContext = struct {
    base_dir: []const u8,
    imported: *ImportSet,
    cache: ?*ImportCache = null,
    depth: u8 = 0,
    max_depth: u8 = 8,
    /// Additional search paths for imports (from --import-path flag).
    import_paths: []const []const u8 = &.{},
};

// ─── Unified Pipeline ──────────────────────────────────────────

/// Flags controlling pipeline behavior.
const CompileFlags = struct {
    resolve_imports: bool = false,
    run_semantic: bool = true,
    merge_imports: bool = false,
    verbose_passes: bool = false,
    json_errors: bool = false,
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
    const raw_lines = try splitLines(alloc, file_data);

    // Resolve @import directives only when enabled and io is available
    const imports_result = if (flags.resolve_imports and import_ctx != null and io != null)
        try resolveImports(io.?, alloc, raw_lines, import_ctx.?)
    else
        null;

    // Use processed lines (with imports stripped) or raw lines
    const final_lines = if (imports_result) |r| r.processed_lines else raw_lines;

    // Tokenize and parse
    const result = try tokenizeAndParseWithLines(alloc, final_lines, flags.json_errors);

    // Merge imported definitions if requested
    var tree = result.tree;
    if (imports_result) |imports| {
        if (imports.templates.len > 0 or imports.tables.len > 0) {
            tree = .{
                .schema = tree.schema,
                .templates = try concatSlices(alloc, ast_mod.Template, tree.templates, imports.templates),
                .tables = try concatSlices(alloc, ast_mod.Table, tree.tables, imports.tables),
                .views = if (flags.merge_imports)
                    try concatSlices(alloc, ast_mod.View, tree.views, imports.views)
                else
                    tree.views,
                .sql_comments = if (flags.merge_imports)
                    try concatSlices(alloc, ast_mod.SqlComment, tree.sql_comments, imports.comments)
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
    return .{ .resolved = result.resolved.?, .lines = result.lines, .tree = result.tree };
}

/// Shared tokenizer → parser → semantic pipeline with verbose pass tracking.
pub fn compilePipelineVerbose(alloc: std.mem.Allocator, file_data: []const u8, verbose: bool, json_errors: bool) !PipelineResult {
    const result = try compileInternal(null, alloc, file_data, null, .{ .verbose_passes = verbose, .json_errors = json_errors });
    return .{ .resolved = result.resolved.?, .lines = result.lines, .tree = result.tree };
}

/// Compile pipeline with import resolution. Handles @import directives by
/// recursively compiling imported files and merging their templates/tables.
fn compilePipelineWithImports(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext, json_errors: bool) !PipelineResult {
    const result = try compileInternal(io, alloc, file_data, import_ctx, .{
        .resolve_imports = true,
        .merge_imports = true,
        .json_errors = json_errors,
    });
    return .{ .resolved = result.resolved.?, .lines = result.lines, .tree = result.tree };
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

/// Concatenate two slices into a new arena-allocated slice.
fn concatSlices(alloc: std.mem.Allocator, comptime T: type, a: []const T, b: []const T) ![]const T {
    var result = try std.ArrayList(T).initCapacity(alloc, a.len + b.len);
    try result.appendSlice(alloc, a);
    try result.appendSlice(alloc, b);
    return try result.toOwnedSlice(alloc);
}

/// Extract the directory portion of a file path.
fn computeBaseDir(alloc: std.mem.Allocator, file_path: []const u8) []const u8 {
    const last_sep = std.mem.lastIndexOfScalar(u8, file_path, '/') orelse
        std.mem.lastIndexOfScalar(u8, file_path, '\\') orelse 0;
    return if (last_sep > 0) alloc.dupe(u8, file_path[0..last_sep]) catch "" else "";
}

/// Split file data into lines, stripping trailing \r.
fn splitLines(alloc: std.mem.Allocator, file_data: []const u8) ![]const []const u8 {
    var lines = try std.ArrayList([]const u8).initCapacity(alloc, 256);
    var line_it = std.mem.splitScalar(u8, file_data, '\n');
    while (line_it.next()) |line| {
        try lines.append(alloc, std.mem.trimEnd(u8, line, "\r"));
    }
    return try lines.toOwnedSlice(alloc);
}

/// Result of resolving @import directives from a set of lines.
const ImportResult = struct {
    processed_lines: []const []const u8,
    templates: []const ast_mod.Template,
    tables: []const ast_mod.Table,
    views: []const ast_mod.View,
    comments: []const ast_mod.SqlComment,
};

/// Shared import resolution logic: iterates lines, resolves @import directives
/// recursively, and returns filtered lines plus accumulated definitions.
fn resolveImports(io: std.Io, alloc: std.mem.Allocator, lines: []const []const u8, import_ctx: *ImportContext) !ImportResult {
    var processed_lines = try std.ArrayList([]const u8).initCapacity(alloc, lines.len);
    var imported_templates = try std.ArrayList(ast_mod.Template).initCapacity(alloc, 8);
    var imported_tables = try std.ArrayList(ast_mod.Table).initCapacity(alloc, 8);
    var imported_views = try std.ArrayList(ast_mod.View).initCapacity(alloc, 8);
    var imported_comments = try std.ArrayList(ast_mod.SqlComment).initCapacity(alloc, 8);

    for (lines) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 8 and std.mem.startsWith(u8, trimmed, "@import")) {
            if (import_ctx.depth >= import_ctx.max_depth) {
                diag.printDiagnostic(.{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "import depth limit exceeded (max 8)",
                    .actual = trimmed,
                });
                return error.ParseError;
            }

            // Extract file path from @import "path" or @import path
            const rest = std.mem.trimStart(u8, trimmed[7..], " ");
            const import_path = if (rest.len >= 2 and rest[0] == '"' and rest[rest.len - 1] == '"')
                rest[1 .. rest.len - 1]
            else
                rest;

            if (import_path.len == 0) {
                diag.printDiagnostic(.{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "@import requires a file path",
                    .actual = trimmed,
                });
                return error.ParseError;
            }

            // Handle std: prefix — search in import_paths
            const resolved_path = if (std.mem.startsWith(u8, import_path, "std:")) blk: {
                const rel_path = import_path[4..];
                // Search in import_paths for the std: relative path
                var found: ?[]const u8 = null;
                for (import_ctx.import_paths) |search_path| {
                    const candidate = std.fmt.allocPrint(alloc, "{s}/{s}", .{ search_path, rel_path }) catch break :blk import_path;
                    // Try reading the file to check if it exists
                    if (std.Io.Dir.cwd().readFileAlloc(io, candidate, alloc, .unlimited)) |_| {
                        found = candidate;
                        break;
                    } else |_| {}
                }
                break :blk found orelse import_path;
            } else if (import_ctx.base_dir.len > 0)
                try std.fmt.allocPrint(alloc, "{s}/{s}", .{ import_ctx.base_dir, import_path })
            else
                try alloc.dupe(u8, import_path);

            // Circular dependency detection
            if (import_ctx.imported.contains(resolved_path)) {
                diag.printDiagnostic(.{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "circular import detected",
                    .actual = resolved_path,
                });
                return error.ParseError;
            }

            // Read imported file
            const imported_data = std.Io.Dir.cwd().readFileAlloc(io, resolved_path, alloc, .unlimited) catch |err| {
                diag.printDiagnostic(.{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "failed to read imported file",
                    .actual = @errorName(err),
                });
                return error.ParseError;
            };

            // Track this import
            try import_ctx.imported.put(resolved_path, {});

            // Check cache before parsing
            var child_tree: ast_mod.Ast = undefined;
            var child_imports: ImportResult = undefined;
            var cache_hit = false;

            if (import_ctx.cache) |cache| {
                if (cache.get(resolved_path)) |cached| {
                    // Cache hit — use stored definitions, skip re-parsing
                    for (cached.templates) |t| try imported_templates.append(alloc, t);
                    for (cached.tables) |t| try imported_tables.append(alloc, t);
                    for (cached.views) |v| try imported_views.append(alloc, v);
                    for (cached.comments) |c| try imported_comments.append(alloc, c);
                    cache_hit = true;
                }
            }

            if (!cache_hit) {
                // Parse imported file: recursively resolve its imports, then tokenize+parse
                var child_ctx = ImportContext{
                    .base_dir = computeBaseDir(alloc, resolved_path),
                    .imported = import_ctx.imported,
                    .cache = import_ctx.cache,
                    .depth = import_ctx.depth + 1,
                };
                const child_lines = try splitLines(alloc, imported_data);
                child_imports = try resolveImports(io, alloc, child_lines, &child_ctx);
                const child_result = try tokenizeAndParseWithLines(alloc, child_imports.processed_lines, false);
                child_tree = child_result.tree;
                if (child_imports.templates.len > 0 or child_imports.tables.len > 0) {
                    child_tree = .{
                        .schema = child_tree.schema,
                        .templates = try concatSlices(alloc, ast_mod.Template, child_tree.templates, child_imports.templates),
                        .tables = try concatSlices(alloc, ast_mod.Table, child_tree.tables, child_imports.tables),
                        .views = child_tree.views,
                        .sql_comments = child_tree.sql_comments,
                    };
                }

                // Merge all definition types
                for (child_tree.templates) |t| try imported_templates.append(alloc, t);
                for (child_tree.tables) |t| try imported_tables.append(alloc, t);
                for (child_tree.views) |v| try imported_views.append(alloc, v);
                for (child_tree.sql_comments) |c| try imported_comments.append(alloc, c);

                // Store in cache for future imports of the same file
                if (import_ctx.cache) |cache| {
                    const cached = CachedImport{
                        .templates = try concatSlices(alloc, ast_mod.Template, child_tree.templates, child_imports.templates),
                        .tables = try concatSlices(alloc, ast_mod.Table, child_tree.tables, child_imports.tables),
                        .views = child_tree.views,
                        .comments = child_tree.sql_comments,
                    };
                    try cache.put(resolved_path, cached);
                }
            }
        } else {
            try processed_lines.append(alloc, line);
        }
    }

    return .{
        .processed_lines = try processed_lines.toOwnedSlice(alloc),
        .templates = try imported_templates.toOwnedSlice(alloc),
        .tables = try imported_tables.toOwnedSlice(alloc),
        .views = try imported_views.toOwnedSlice(alloc),
        .comments = try imported_comments.toOwnedSlice(alloc),
    };
}

/// Tokenize and parse a .ss file into AST and tokenized lines.
/// Returns both the parsed tree and the tokenized lines so callers
/// don't need to re-tokenize for trace output.
fn tokenizeAndParseWithLines(alloc: std.mem.Allocator, lines: []const []const u8, json_errors: bool) !struct { tree: ast_mod.Ast, tokenized: []tokenizer.Line } {
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    diagnostics.json_errors = json_errors;
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    const tree = p.parse(tokenized) catch |err| {
        if (!diagnostics.hasErrors()) {
            std.debug.print("error: {s}\n", .{@errorName(err)});
        }
        return err;
    };
    if (diagnostics.hasErrors()) {
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.DiagnosticsError;
    }
    return .{ .tree = tree, .tokenized = tokenized };
}

// ─── Public API ────────────────────────────────────────────────

/// Compile a .ss file by path, handling @import directives.
pub fn compileFile(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, json_errors: bool) !PipelineResult {
    return compileFileWithPaths(io, alloc, file_path, &.{}, json_errors);
}

/// Compile a .ss file by path with additional import search paths.
pub fn compileFileWithPaths(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, import_paths: []const []const u8, json_errors: bool) !PipelineResult {
    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, file_path, alloc, .unlimited);
    const base_dir = computeBaseDir(alloc, file_path);

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
    input: ?[]const u8, // null = stdin, else = file path
    output_path: ?[]const u8,
    trace: bool,
    dialect: codegen.Dialect,
    format: OutputFormat,
    stats: bool,
    check: bool,
    quiet: bool,
    verbose_passes: bool,
    json_errors: bool,
    import_paths: []const []const u8,
) !void {
    const pipeline = if (input) |path|
        try compileFileWithPaths(io, alloc, path, import_paths, json_errors)
    else
        try compilePipelineVerbose(alloc, try io_mod.readStdin(io, alloc), verbose_passes, json_errors);

    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);

    const output = switch (format) {
        .sql => blk: {
            var cg = codegen.Codegen.init(alloc, dialect);
            break :blk try cg.generateFromTypedAst(typed);
        },
        .json_schema => blk: {
            break :blk try json_schema.generate(alloc, typed);
        },
    };

    if (trace) {
        if (format == .sql) traceWithTyped(pipeline, typed) else traceForward(pipeline);
    }

    if (stats) {
        printStats(computeStats(pipeline.resolved));
    }

    if (check) {
        if (!quiet) {
            std.debug.print("schema is valid\n", .{});
        }
        return;
    }

    try io_mod.writeOutput(io, output, output_path, quiet);
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
