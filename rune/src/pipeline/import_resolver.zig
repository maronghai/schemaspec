const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const tokenizer = @import("../parser/tokenizer.zig");
const parser = @import("../parser/parser.zig");
const diag = @import("../diagnostic.zig");

// ─── Import Resolution ─────────────────────────────────────────
// Handles @import directives during .ss file compilation.
// Extracted from forward.zig for single-responsibility.

/// Maximum recursion depth for @import directives. Prevents infinite loops
/// from circular imports. Must match the value in the error message below.
pub const MAX_IMPORT_DEPTH = 8;

/// Set of imported file paths for circular dependency detection.
pub const ImportSet = std.StringHashMap(void);

/// Cached parse result for a previously imported file.
pub const CachedImport = struct {
    templates: []const ast_mod.Template,
    tables: []const ast_mod.Table,
    views: []const ast_mod.View,
    comments: []const ast_mod.SqlComment,
    composites: []const ast_mod.Composite = &.{},
};

/// Cache of parsed import files — keyed by resolved path.
pub const ImportCache = std.StringHashMap(CachedImport);

/// Context for resolving @import directives during parsing.
pub const ImportContext = struct {
    base_dir: []const u8,
    imported: *ImportSet,
    /// Files on the current recursion path — a file found here is a TRUE
    /// cycle. `imported` alone can't distinguish a diamond (main→a, main→b,
    /// both→common) from a cycle; this set is push-on-enter/pop-on-done.
    in_progress: ?*ImportSet = null,
    cache: ?*ImportCache = null,
    depth: u8 = 0,
    max_depth: u8 = MAX_IMPORT_DEPTH,
    /// Additional search paths for imports (from --import-path flag).
    import_paths: []const []const u8 = &.{},
    /// When non-null, parse errors from imported children accumulate here so
    /// the caller can fold them into the root tree's error_count (exit codes,
    /// CI gates). Null = don't track (tests).
    accumulated_errors: ?*usize = null,
    /// JSON error formatting for child-file parse diagnostics (--json-errors
    /// must reach imports too, or output becomes mixed-format).
    json_errors: bool = false,
};

/// Result of resolving @import directives from a set of lines.
pub const ImportResult = struct {
    processed_lines: []const []const u8,
    templates: []const ast_mod.Template,
    tables: []const ast_mod.Table,
    views: []const ast_mod.View,
    comments: []const ast_mod.SqlComment,
    composites: []const ast_mod.Composite = &.{},
};

/// Split file data into lines, stripping trailing \r.
pub fn splitLines(alloc: std.mem.Allocator, file_data: []const u8) ![]const []const u8 {
    var lines = try std.ArrayList([]const u8).initCapacity(alloc, 256);
    var line_it = std.mem.splitScalar(u8, file_data, '\n');
    while (line_it.next()) |line| {
        try lines.append(alloc, std.mem.trimEnd(u8, line, "\r"));
    }
    return try lines.toOwnedSlice(alloc);
}

/// Extract the directory portion of a file path.
pub fn computeBaseDir(alloc: std.mem.Allocator, file_path: []const u8) []const u8 {
    const last_sep = std.mem.lastIndexOfScalar(u8, file_path, '/') orelse
        std.mem.lastIndexOfScalar(u8, file_path, '\\') orelse 0;
    return if (last_sep > 0) alloc.dupe(u8, file_path[0..last_sep]) catch "" else "";
}

/// Concatenate two slices into a new arena-allocated slice.
pub fn concatSlices(alloc: std.mem.Allocator, comptime T: type, a: []const T, b: []const T) ![]const T {
    var result = try std.ArrayList(T).initCapacity(alloc, a.len + b.len);
    try result.appendSlice(alloc, a);
    try result.appendSlice(alloc, b);
    return try result.toOwnedSlice(alloc);
}

/// Tokenize and parse a .ss file into AST and tokenized lines.
/// Returns both the parsed tree and the tokenized lines so callers
/// don't need to re-tokenize for trace output.
/// The tree is always returned (even on errors) — check tree.error_count
/// for the number of parse errors. The pipeline can then attempt semantic
/// analysis on the partial AST to discover additional errors.
pub fn tokenizeAndParseWithLines(alloc: std.mem.Allocator, lines: []const []const u8, json_errors: bool) !struct { tree: ast_mod.Ast, tokenized: []tokenizer.Line } {
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    defer diagnostics.diagnostics.deinit(alloc);
    diagnostics.json_errors = json_errors;
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    // Parser always succeeds when diagnostics are present — errors are recorded
    // in the DiagnosticCollector and the tree contains all successfully parsed elements.
    var tree = try p.parse(tokenized);
    if (diagnostics.hasErrors()) {
        tree.error_count = diagnostics.errorCount();
        diagnostics.printAll();
        diagnostics.printSummary();
    }
    return .{ .tree = tree, .tokenized = tokenized };
}

/// Tokenize and parse without printing errors. Returns the tree with
/// error_count set. Used by the pipeline for multi-error recovery —
/// errors are collected and printed together at the end.
pub fn tokenizeAndParseLenient(alloc: std.mem.Allocator, lines: []const []const u8) !struct { tree: ast_mod.Ast, tokenized: []tokenizer.Line } {
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    var tree = try p.parse(tokenized);
    if (diagnostics.hasErrors()) {
        tree.error_count = diagnostics.errorCount();
    }
    return .{ .tree = tree, .tokenized = tokenized };
}

/// Tokenize and parse silently, handing the caller the collected parse
/// diagnostics instead of printing them to stderr. The returned slice is
/// allocated with `alloc` (arena-style callers get cleanup for free) and
/// each diagnostic's message is duped into `alloc`, so the collector may be
/// deinit'd afterwards. Used by the LSP compile service, which must surface
/// per-error ranges to editors rather than a generic "has errors" marker.
pub fn tokenizeAndParseQuiet(
    alloc: std.mem.Allocator,
    lines: []const []const u8,
    out_diagnostics: *[]const diag.Diagnostic,
) !struct { tree: ast_mod.Ast, tokenized: []tokenizer.Line } {
    const tok = tokenizer.Tokenizer.init(lines);
    const tokenized = try tok.tokenizeAll(alloc);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    var tree = try p.parse(tokenized);
    if (diagnostics.hasErrors()) {
        tree.error_count = diagnostics.errorCount();
    }
    var collected = try std.ArrayList(diag.Diagnostic).initCapacity(alloc, diagnostics.diagnostics.items.len);
    for (diagnostics.diagnostics.items) |d| {
        var copy = d;
        if (d.message.len > 0) copy.message = try alloc.dupe(u8, d.message);
        try collected.append(alloc, copy);
    }
    out_diagnostics.* = try collected.toOwnedSlice(alloc);
    return .{ .tree = tree, .tokenized = tokenized };
}

/// Shared import resolution logic: iterates lines, resolves @import directives
/// recursively, and returns filtered lines plus accumulated definitions.
pub fn resolveImports(io: std.Io, alloc: std.mem.Allocator, lines: []const []const u8, import_ctx: *ImportContext) !ImportResult {
    var processed_lines = try std.ArrayList([]const u8).initCapacity(alloc, lines.len);
    var imported_templates = try std.ArrayList(ast_mod.Template).initCapacity(alloc, 8);
    var imported_tables = try std.ArrayList(ast_mod.Table).initCapacity(alloc, 8);
    var imported_views = try std.ArrayList(ast_mod.View).initCapacity(alloc, 8);
    var imported_comments = try std.ArrayList(ast_mod.SqlComment).initCapacity(alloc, 8);
    var imported_composites = try std.ArrayList(ast_mod.Composite).initCapacity(alloc, 4);

    for (lines) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 8 and std.mem.startsWith(u8, trimmed, "@import")) {
            if (import_ctx.depth >= import_ctx.max_depth) {
                diag.printDiagnostic(alloc, .{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = std.fmt.comptimePrint("import depth limit exceeded (max {d})", .{MAX_IMPORT_DEPTH}),
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
                diag.printDiagnostic(alloc, .{
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
                if (found == null and import_ctx.import_paths.len > 0) {
                    diag.printDiagnostic(alloc, .{
                        .severity = .warning,
                        .line_no = 0,
                        .message = "std: import path not found in any search path — falling back to literal path",
                        .actual = import_path,
                    });
                }
                break :blk found orelse import_path;
            } else if (import_ctx.base_dir.len > 0)
                try std.fmt.allocPrint(alloc, "{s}/{s}", .{ import_ctx.base_dir, import_path })
            else
                try alloc.dupe(u8, import_path);

            // Cycle detection: only a file on the CURRENT recursion path is a
            // true cycle. A file that was already fully imported (visited set)
            // but is not in progress is a diamond/repeat — reuse its cache and
            // skip, without error.
            if (import_ctx.in_progress) |stack| {
                if (stack.contains(resolved_path)) {
                    diag.printDiagnostic(alloc, .{
                        .severity = .@"error",
                        .line_no = 0,
                        .message = "circular import detected",
                        .actual = resolved_path,
                    });
                    return error.ParseError;
                }
            }

            // Read imported file
            const imported_data = std.Io.Dir.cwd().readFileAlloc(io, resolved_path, alloc, .unlimited) catch {
                diag.printDiagnostic(alloc, .{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "failed to read imported file",
                    .actual = import_path,
                });
                return error.ParseError;
            };

            // Already merged earlier in this compile (diamond or repeat)?
            // Its definitions are already in the merged result — skip without
            // duplicating them.
            if (import_ctx.imported.contains(resolved_path)) {
                continue;
            }

            // Track this import
            try import_ctx.imported.put(resolved_path, {});

            // Push onto the recursion path for the duration of child resolution
            var stack_set: ImportSet = undefined;
            var own_stack = false;
            var active_stack: *ImportSet = undefined;
            if (import_ctx.in_progress) |outer| {
                active_stack = outer;
            } else {
                stack_set = ImportSet.init(alloc);
                own_stack = true;
                active_stack = &stack_set;
                import_ctx.in_progress = active_stack;
            }
            try active_stack.put(resolved_path, {});
            defer {
                _ = active_stack.remove(resolved_path);
                if (own_stack) import_ctx.in_progress = null;
            }

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
                    for (cached.composites) |c| try imported_composites.append(alloc, c);
                    cache_hit = true;
                }
            }

            if (!cache_hit) {
                // Parse imported file: recursively resolve its imports, then tokenize+parse
                var child_ctx = ImportContext{
                    .base_dir = computeBaseDir(alloc, resolved_path),
                    .imported = import_ctx.imported,
                    .in_progress = import_ctx.in_progress,
                    .cache = import_ctx.cache,
                    .depth = import_ctx.depth + 1,
                    .import_paths = import_ctx.import_paths,
                    .accumulated_errors = import_ctx.accumulated_errors,
                    .json_errors = import_ctx.json_errors,
                };
                const child_lines = try splitLines(alloc, imported_data);
                child_imports = try resolveImports(io, alloc, child_lines, &child_ctx);
                const child_result = try tokenizeAndParseWithLines(alloc, child_imports.processed_lines, import_ctx.json_errors);
                child_tree = child_result.tree;
                // A broken import is a broken compile: fold the child's error
                // count into the root's tally so exit codes / CI gates see it
                // (previously only the root file's own errors were counted).
                if (child_tree.error_count > 0) {
                    if (import_ctx.accumulated_errors) |acc| {
                        acc.* += child_tree.error_count;
                    }
                }
                if (child_imports.templates.len > 0 or child_imports.tables.len > 0) {
                    child_tree = .{
                        .schema = child_tree.schema,
                        .templates = try concatSlices(alloc, ast_mod.Template, child_tree.templates, child_imports.templates),
                        .tables = try concatSlices(alloc, ast_mod.Table, child_tree.tables, child_imports.tables),
                        .views = child_tree.views,
                        .sql_comments = child_tree.sql_comments,
                        .composites = try concatSlices(alloc, ast_mod.Composite, child_tree.composites, child_imports.composites),
                    };
                }

                // Merge all definition types
                for (child_tree.templates) |t| try imported_templates.append(alloc, t);
                for (child_tree.tables) |t| try imported_tables.append(alloc, t);
                for (child_tree.views) |v| try imported_views.append(alloc, v);
                for (child_tree.sql_comments) |c| try imported_comments.append(alloc, c);
                for (child_tree.composites) |c| try imported_composites.append(alloc, c);

                // Store in cache for future imports of the same file
                if (import_ctx.cache) |cache| {
                    const cached = CachedImport{
                        .templates = try concatSlices(alloc, ast_mod.Template, child_tree.templates, child_imports.templates),
                        .tables = try concatSlices(alloc, ast_mod.Table, child_tree.tables, child_imports.tables),
                        .views = child_tree.views,
                        .comments = child_tree.sql_comments,
                        .composites = try concatSlices(alloc, ast_mod.Composite, child_tree.composites, child_imports.composites),
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
        .composites = try imported_composites.toOwnedSlice(alloc),
    };
}
