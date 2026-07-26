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

/// Context for resolving @import directives during parsing.
pub const ImportContext = struct {
    base_dir: []const u8,
    imported: *ImportSet,
    depth: u8 = 0,
    max_depth: u8 = 8,
};

/// Shared tokenizer → parser → semantic pipeline.
/// Returns PipelineResult with all intermediate IRs for trace inspection.
pub fn compilePipeline(alloc: std.mem.Allocator, file_data: []const u8) !PipelineResult {
    const lines = try splitLines(alloc, file_data);
    const tree = try tokenizeAndParse(alloc, lines);
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);

    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = sa.analyze(tree) catch |err| {
        return err;
    };

    return .{ .resolved = resolved, .lines = tokenized, .tree = tree };
}

/// Compile pipeline with import resolution. Handles @import directives by
/// recursively compiling imported files and merging their templates/tables.
fn compilePipelineWithImports(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext) !PipelineResult {
    const tokenized_lines = try splitLines(alloc, file_data);

    // Process @import directives before tokenization
    var processed_lines = try std.ArrayList([]const u8).initCapacity(alloc, tokenized_lines.len);
    var imported_templates = try std.ArrayList(ast_mod.Template).initCapacity(alloc, 8);
    var imported_tables = try std.ArrayList(ast_mod.Table).initCapacity(alloc, 8);
    var imported_views = try std.ArrayList(ast_mod.View).initCapacity(alloc, 8);
    var imported_comments = try std.ArrayList(ast_mod.SqlComment).initCapacity(alloc, 8);

    for (tokenized_lines) |line| {
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

            // Resolve path relative to base directory
            const resolved_path = if (import_ctx.base_dir.len > 0)
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

            // Parse imported file (templates + tables only, no semantic analysis)
            const imported_tree = try parseOnly(io, alloc, imported_data, import_ctx);

            // Merge templates, tables, views, and SQL comments (skip schema)
            for (imported_tree.templates) |t| {
                try imported_templates.append(alloc, t);
            }
            for (imported_tree.tables) |t| {
                try imported_tables.append(alloc, t);
            }
            for (imported_tree.views) |v| {
                try imported_views.append(alloc, v);
            }
            for (imported_tree.sql_comments) |c| {
                try imported_comments.append(alloc, c);
            }
        } else {
            try processed_lines.append(alloc, line);
        }
    }

    // Tokenize processed lines (imports removed)
    const tok = tokenizer.Tokenizer.init(try processed_lines.toOwnedSlice(alloc));
    const tokenized = try tok.tokenizeAll(alloc);

    // Use DiagnosticCollector for multi-error recovery
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    var tree = p.parse(tokenized) catch |err| {
        if (!diagnostics.hasErrors()) {
            std.debug.print("error: {s}\n", .{@errorName(err)});
        }
        return err;
    };

    // Print collected diagnostics and abort if any errors
    if (diagnostics.hasErrors()) {
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.DiagnosticsError;
    }

    // Merge imported definitions into parsed tree
    if (imported_templates.items.len > 0 or imported_tables.items.len > 0) {
        tree = .{
            .schema = tree.schema,
            .templates = try concatSlices(alloc, ast_mod.Template, tree.templates, try imported_templates.toOwnedSlice(alloc)),
            .tables = try concatSlices(alloc, ast_mod.Table, tree.tables, try imported_tables.toOwnedSlice(alloc)),
            .views = try concatSlices(alloc, ast_mod.View, tree.views, try imported_views.toOwnedSlice(alloc)),
            .sql_comments = try concatSlices(alloc, ast_mod.SqlComment, tree.sql_comments, try imported_comments.toOwnedSlice(alloc)),
        };
    }

    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = sa.analyze(tree) catch |err| {
        return err;
    };

    return .{ .resolved = resolved, .lines = tokenized, .tree = tree };
}

/// Tokenize and parse a .ss file, resolving @import directives recursively.
/// Used for importing templates and tables from other files.
fn parseOnly(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, import_ctx: *ImportContext) !ast_mod.Ast {
    const lines = try splitLines(alloc, file_data);

    // Process @import directives
    var processed_lines = try std.ArrayList([]const u8).initCapacity(alloc, lines.len);
    var imported_templates = try std.ArrayList(ast_mod.Template).initCapacity(alloc, 8);
    var imported_tables = try std.ArrayList(ast_mod.Table).initCapacity(alloc, 8);

    for (lines) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 8 and std.mem.startsWith(u8, trimmed, "@import")) {
            if (import_ctx.depth >= import_ctx.max_depth) {
                return error.ParseError;
            }
            const rest = std.mem.trimStart(u8, trimmed[7..], " ");
            const import_path = if (rest.len >= 2 and rest[0] == '"' and rest[rest.len - 1] == '"')
                rest[1 .. rest.len - 1]
            else
                rest;
            if (import_path.len == 0) return error.ParseError;

            const resolved_path = if (import_ctx.base_dir.len > 0)
                try std.fmt.allocPrint(alloc, "{s}/{s}", .{ import_ctx.base_dir, import_path })
            else
                try alloc.dupe(u8, import_path);

            if (import_ctx.imported.contains(resolved_path)) return error.ParseError;

            const imported_data = std.Io.Dir.cwd().readFileAlloc(
                io,
                resolved_path,
                alloc,
                .unlimited,
            ) catch return error.ParseError;

            try import_ctx.imported.put(resolved_path, {});

            var child_ctx = ImportContext{
                .base_dir = computeBaseDir(alloc, resolved_path),
                .imported = import_ctx.imported,
                .depth = import_ctx.depth + 1,
            };

            const child_tree = try parseOnly(io, alloc, imported_data, &child_ctx);
            for (child_tree.templates) |t| try imported_templates.append(alloc, t);
            for (child_tree.tables) |t| try imported_tables.append(alloc, t);
        } else {
            try processed_lines.append(alloc, line);
        }
    }

    const tok = tokenizer.Tokenizer.init(try processed_lines.toOwnedSlice(alloc));
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    var tree = p.parse(tokenized) catch |err| {
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

    // Merge imported definitions
    if (imported_templates.items.len > 0 or imported_tables.items.len > 0) {
        tree = .{
            .schema = tree.schema,
            .templates = try concatSlices(alloc, ast_mod.Template, tree.templates, try imported_templates.toOwnedSlice(alloc)),
            .tables = try concatSlices(alloc, ast_mod.Table, tree.tables, try imported_tables.toOwnedSlice(alloc)),
            .views = tree.views,
            .sql_comments = tree.sql_comments,
        };
    }

    return tree;
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

/// Tokenize lines and parse into AST with diagnostic error handling.
fn tokenizeAndParse(alloc: std.mem.Allocator, lines: []const []const u8) !ast_mod.Ast {
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
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
    return tree;
}

// ─── Public API ────────────────────────────────────────────────

/// Compile a .ss file by path, handling @import directives.
pub fn compileFile(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8) !PipelineResult {
    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, file_path, alloc, .unlimited);
    const base_dir = computeBaseDir(alloc, file_path);

    var imported = ImportSet.init(alloc);
    defer imported.deinit();

    // Track the initial file to prevent self-import
    try imported.put(file_path, {});

    var ctx = ImportContext{
        .base_dir = base_dir,
        .imported = &imported,
    };

    return compilePipelineWithImports(io, alloc, file_data, &ctx);
}

/// Compile a .ss file path to ResolvedAst (used by diff/migrate pipelines).
pub fn compileToAst(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !resolved_ast.ResolvedAst {
    const pipeline = try compileFile(io, alloc, path);
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

// ─── Output Handlers ───────────────────────────────────────────

/// Compile .ss to SQL DDL (the default output path).
pub fn handleCompile(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, output_path: ?[]const u8, trace: bool, dialect: codegen.Dialect) !void {
    const pipeline = try compilePipeline(alloc, file_data);
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);
    var cg = codegen.Codegen.init(alloc, dialect);
    const output = try cg.generateFromTypedAst(typed);
    if (trace) traceWithTyped(pipeline, typed);
    try io_mod.writeOutput(io, output, output_path);
}

/// Compile .ss from a file path, handling imports, to SQL DDL.
pub fn handleCompileFile(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, output_path: ?[]const u8, trace: bool, dialect: codegen.Dialect) !void {
    const pipeline = try compileFile(io, alloc, file_path);
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);
    var cg = codegen.Codegen.init(alloc, dialect);
    const output = try cg.generateFromTypedAst(typed);
    if (trace) traceWithTyped(pipeline, typed);
    try io_mod.writeOutput(io, output, output_path);
}

/// Compile .ss to JSON Schema (alternative output path).
pub fn handleCompileJsonSchema(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, output_path: ?[]const u8, trace: bool, dialect: codegen.Dialect) !void {
    const json_schema = @import("../json_schema.zig");
    const pipeline = try compilePipeline(alloc, file_data);
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);
    const output = try json_schema.generate(alloc, typed);
    if (trace) traceForward(pipeline);
    try io_mod.writeOutput(io, output, output_path);
}

/// Compile .ss from a file path, handling imports, to JSON Schema.
pub fn handleCompileJsonSchemaFile(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, output_path: ?[]const u8, trace: bool, dialect: codegen.Dialect) !void {
    const json_schema = @import("../json_schema.zig");
    const pipeline = try compileFile(io, alloc, file_path);
    const typed = try TypeResolver.resolve(alloc, pipeline.resolved, dialect);
    const output = try json_schema.generate(alloc, typed);
    if (trace) traceForward(pipeline);
    try io_mod.writeOutput(io, output, output_path);
}

/// Validate a .ss file — runs the full semantic pipeline and reports diagnostics.
/// Returns error.DiagnosticsError if any errors are found (exit code 1).
pub fn handleValidate(_: std.Io, alloc: std.mem.Allocator, file_data: []const u8) !void {
    _ = try compilePipeline(alloc, file_data);
    std.debug.print("schema is valid\n", .{});
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "compilePipeline: simple schema produces resolved tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const result = try compilePipeline(alloc, ss_input);
    try testing.expect(result.resolved.tables.len > 0);
    try testing.expectEqualStrings("user", result.resolved.tables[0].name);
}

test "compilePipeline: syntax error returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const bad_input = "### invalid $$$";
    const result = compilePipeline(alloc, bad_input);
    try testing.expectError(error.ParseError, result);
}
