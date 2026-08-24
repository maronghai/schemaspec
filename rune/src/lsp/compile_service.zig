const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const import_res = @import("../pipeline/import_resolver.zig");
const semantic = @import("../semantic/analyzer.zig");
const diag_mod = @import("../diagnostic.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const resolved_ast = @import("../types/resolved_ast.zig");
const codegen = @import("../codegen/codegen.zig");
const lsp_protocol = @import("protocol.zig");
const Diagnostic = lsp_protocol.Diagnostic;
const DiagnosticSeverity = lsp_protocol.DiagnosticSeverity;
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const helpers = @import("helpers.zig");
const lineNoToZeroBased = helpers.lineNoToZeroBased;

// ─── LSP Compile Service ───────────────────────────────────────
// Wraps the Rune compilation pipeline for LSP use.
// Captures diagnostics from all pipeline stages and converts
// them to LSP Diagnostic format for publishing to editors.
// Caches the TypedAst for use by interactive LSP features.
//
// All intermediate allocations (AST, tokenizer, resolved tables) are
// managed via an arena allocator passed by the caller. This is the
// standard pattern for pipeline code in the LSP server.

pub const CompileResult = struct {
    diagnostics: []const Diagnostic,
    typed_ast: ?TypedAst = null,
};

/// Compile a schema text and return LSP diagnostics.
/// Runs the full pipeline: tokenize → parse → semantic → type resolve.
/// Captures diagnostics at each stage.
/// Uses the provided allocator for all intermediate allocations.
/// The caller owns all returned memory; use an arena allocator for
/// automatic cleanup of pipeline intermediates.
pub fn compile(alloc: std.mem.Allocator, text: []const u8, file_path: []const u8, dialect: Dialect) !CompileResult {
    _ = file_path;
    var diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 16);

    // Split the document into lines exactly like the main pipeline
    // (import_resolver.splitLines) — the tokenizer is line-oriented and
    // treats each slice as one physical line. Passing the whole document
    // as a single "line" collapses every AST-based feature to garbage.
    const lines = import_res.splitLines(alloc, text) catch |err| {
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 0 },
            },
            .severity = .error_sev,
            .message = switch (err) {
                error.OutOfMemory => "Out of memory",
            },
        }) catch {};
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };

    // Stage 1: Tokenize and parse — collect per-error diagnostics instead of
    // printing them to stderr; editors need each error's real location.
    // The parser prints some diagnostics directly via printDiagnostic; routing
    // them into a collector captures those too (single-threaded LSP only).
    var parse_diagnostics: []const diag_mod.Diagnostic = &.{};
    var capture = diag_mod.DiagnosticCollector.init(alloc) catch {
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };
    defer capture.diagnostics.deinit(alloc);
    const prev_collector = diag_mod.active_collector;
    diag_mod.active_collector = &capture;
    defer diag_mod.active_collector = prev_collector;

    const tokenized = import_res.tokenizeAndParseQuiet(alloc, lines, &parse_diagnostics) catch |err| {
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 0 },
            },
            .severity = .error_sev,
            .message = switch (err) {
                error.OutOfMemory => "Out of memory",
                else => "Parse error",
            },
        }) catch {};
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };

    for (parse_diagnostics) |d| {
        const severity: DiagnosticSeverity = switch (d.severity) {
            .@"error" => .error_sev,
            .warning => .warning,
            .note => .information,
        };
        const line = lineNoToZeroBased(d.line_no);
        const col: u32 = if (d.col) |c| @intCast(c -| 1) else 0;
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = line, .character = col },
                .end = .{ .line = line, .character = col + 1 },
            },
            .severity = severity,
            .message = d.message,
        }) catch {};
    }
    // Diagnostics the parser emitted through its direct-print path (warnings,
    // recovery errors) were routed into `capture` by the active_collector hook.
    for (capture.diagnostics.items) |d| {
        const severity: DiagnosticSeverity = switch (d.severity) {
            .@"error" => .error_sev,
            .warning => .warning,
            .note => .information,
        };
        const line = lineNoToZeroBased(d.line_no);
        const col: u32 = if (d.col) |c| @intCast(c -| 1) else 0;
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = line, .character = col },
                .end = .{ .line = line, .character = col + 1 },
            },
            .severity = severity,
            .message = d.message,
        }) catch {};
    }

    const tree = tokenized.tree;

    // Stage 2: Semantic analysis with diagnostic capture
    var collector = diag_mod.DiagnosticCollector.init(alloc) catch {
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };
    defer collector.diagnostics.deinit(alloc);

    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = sa.analyzeWithCollector(tree, &collector);

    // Free tokenizer output — not needed after semantic analysis.
    // ResolvedAst references AST fields (not tokenizer Lines), so this is safe.
    alloc.free(tokenized.tokenized);

    // Convert captured diagnostics to LSP format
    for (collector.diagnostics.items) |d| {
        const severity: DiagnosticSeverity = switch (d.severity) {
            .@"error" => .error_sev,
            .warning => .warning,
            .note => .information,
        };
        const line = lineNoToZeroBased(d.line_no);
        const col: u32 = if (d.col) |c| @intCast(c -| 1) else 0;
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = line, .character = col },
                .end = .{ .line = line, .character = col + 1 },
            },
            .severity = severity,
            .message = d.message,
        }) catch {};
    }

    // If semantic analysis failed, we already have diagnostics
    _ = resolved catch |err| {
        if (err != error.SemanticError) {
            diagnostics.append(alloc, .{
                .range = .{
                    .start = .{ .line = 0, .character = 0 },
                    .end = .{ .line = 0, .character = 0 },
                },
                .severity = .error_sev,
                .message = "Internal compilation error",
            }) catch {};
        }
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };

    // Stage 3: Type resolution (for additional diagnostics + TypedAst)
    var typed_ast: ?TypedAst = null;
    if (resolved) |r| {
        typed_ast = resolveTypedAst(alloc, r, &diagnostics, dialect);
    } else |_| {
        // Semantic analysis failed — diagnostics already captured
    }

    return .{
        .diagnostics = diagnostics.toOwnedSlice(alloc) catch &.{},
        .typed_ast = typed_ast,
    };
}

fn resolveTypedAst(alloc: std.mem.Allocator, resolved: resolved_ast.ResolvedAst, diagnostics: *std.ArrayList(Diagnostic), dialect: Dialect) ?TypedAst {
    return TypeResolver.resolve(alloc, resolved, dialect) catch |err| {
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 0 },
            },
            .severity = .error_sev,
            .message = switch (err) {
                error.OutOfMemory => "Out of memory",
                else => "Type resolution error",
            },
        }) catch {};
        return null;
    };
}

// ─── Tests ─────────────────────────────────────────────────────
// Tests use arena allocators to match the LSP server's actual usage pattern.
// Pipeline intermediates (AST, tokenizer, resolved tables) are owned by the arena.

test "compile valid schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc,
        \\# users {
        \\  id    n   ++
        \\  name  s64
        \\}
    , "test.ss", .mysql);

    // Valid schema should have no errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false); // Should not have errors
        }
    }
}

test "multi-line document parses into real tables (LSP pipeline parity)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc,
        \\# users
        \\id n ++
        \\name s32
        \\
        \\# orders
        \\id n ++
        \\user_id n > users.id
    , "test.ss", .mysql);

    // The document must be split into lines before parsing — the whole
    // point of the LSP compile service is to see the same AST as `rune compile`.
    const typed = result.typed_ast orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), typed.tables.len);
    try std.testing.expectEqualStrings("users", typed.tables[0].name);
    try std.testing.expectEqualStrings("orders", typed.tables[1].name);

    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false); // valid schema must not produce errors
        }
    }
}

test "parse errors surface as per-error diagnostics with real locations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // An unterminated CHECK-style bracket is a hard parse error; the LSP
    // must surface the parser's own diagnostic (with its real line) rather
    // than a single vague "has errors" marker.
    const result = try compile(alloc,
        \\# users
        \\id n ++
        \\name s32 [0,
        \\# posts
        \\title s64
    , "test.ss", .mysql);

    try std.testing.expect(result.diagnostics.len > 0);
    var saw_error = false;
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            saw_error = true;
            // The unclosed bracket starts on line index 2 (0-based).
            try std.testing.expectEqual(@as(u32, 2), d.range.start.line);
        }
    }
    try std.testing.expect(saw_error);
}

test "unrecognized tokens surface as warnings pinned to their own line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Lenient recovery: `??? garbage ???` warns (field named ???), it does
    // not abort — but the warning must carry the right line to the editor.
    const result = try compile(alloc,
        \\# users
        \\id n ++
        \\??? garbage ???
    , "test.ss", .mysql);

    var saw_warning_on_line_2 = false;
    for (result.diagnostics) |d| {
        if (d.severity == .warning and d.range.start.line == 2) {
            saw_warning_on_line_2 = true;
        }
    }
    try std.testing.expect(saw_warning_on_line_2);
}

test "compile invalid schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Verify compilation works even with unusual input (parser is lenient)
    const result = try compile(alloc,
        \\# user
        \\  id n
        \\  > nonexistent.id
    , "test.ss", .mysql);

    // Compilation should succeed without crashing
    // (the parser is lenient; semantic errors may or may not produce diagnostics)
    _ = result;
}

test "compile empty schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc, "", "test.ss", .mysql);

    // Empty schema should compile without errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false);
        }
    }
}

test "compile schema with foreign key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc,
        \\table users {
        \\  id n ++ PK
        \\}
        \\
        \\table posts {
        \\  id      n  ++ PK
        \\  user_id n  -> users.id
        \\}
    , "test.ss", .mysql);

    // Valid schema with FK should have no errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false);
        }
    }
}

test "compile syntax error: unclosed table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The parser is lenient — unclosed tables are tolerated
    const result = try compile(alloc,
        \\table users {
        \\  id n ++ PK
    , "test.ss", .mysql);

    // Parser is lenient; compilation should succeed without crashing
    // Diagnostics may or may not be produced
    _ = result;
}

test "compile semantic error: FK to nonexistent table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The semantic analyzer is lenient — FK to nonexistent tables are tolerated
    const result = try compile(alloc,
        \\table posts {
        \\  id      n  ++ PK
        \\  user_id n  -> nonexistent.id
        \\}
    , "test.ss", .mysql);

    // Compilation should succeed without crashing
    _ = result;
}

test "compile schema with multiple FK references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc,
        \\table posts {
        \\  id      n  ++ PK
        \\  user_id n  -> a.b
        \\  tag_id  n  -> c.d
        \\}
    , "test.ss", .mysql);

    // Compilation should succeed without crashing
    _ = result;
}

test "compile schema with template only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try compile(alloc,
        \\~timestamps {
        \\  created_at dt
        \\  updated_at dt
        \\}
    , "test.ss", .mysql);

    // Template-only schema should compile without errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false);
        }
    }
}
