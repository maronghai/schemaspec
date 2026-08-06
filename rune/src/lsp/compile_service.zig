const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const import_res = @import("../pipeline/import_resolver.zig");
const semantic = @import("../semantic/analyzer.zig");
const diag_mod = @import("../semantic/diagnostic.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const resolved_ast = @import("../types/resolved_ast.zig");
const codegen = @import("../codegen/codegen.zig");
const lsp_protocol = @import("protocol.zig");
const Diagnostic = lsp_protocol.Diagnostic;
const DiagnosticSeverity = lsp_protocol.DiagnosticSeverity;
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── LSP Compile Service ───────────────────────────────────────
// Wraps the Rune compilation pipeline for LSP use.
// Captures diagnostics from all pipeline stages and converts
// them to LSP Diagnostic format for publishing to editors.
// Caches the TypedAst for use by interactive LSP features.

pub const CompileResult = struct {
    diagnostics: []const Diagnostic,
    typed_ast: ?TypedAst = null,
};

/// Compile a schema text and return LSP diagnostics.
/// Runs the full pipeline: tokenize → parse → semantic → type resolve.
/// Captures diagnostics at each stage.
pub fn compile(alloc: std.mem.Allocator, text: []const u8, file_path: []const u8, dialect: Dialect) !CompileResult {
    _ = file_path;
    var diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 16);

    // Stage 1: Tokenize and parse
    const tokenized = import_res.tokenizeAndParseWithLines(alloc, &.{text}, false) catch |err| {
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

    const tree = tokenized.tree;

    // Collect parse errors from the AST
    if (tree.error_count > 0) {
        // Parse errors exist but details are embedded in the AST structure.
        // Report a general parse error with location from the first table.
        const first_loc: usize = if (tree.tables.len > 0) tree.tables[0].line_no else 1;
        diagnostics.append(alloc, .{
            .range = .{
                .start = .{ .line = @intCast(first_loc -| 1), .character = 0 },
                .end = .{ .line = @intCast(first_loc -| 1), .character = 100 },
            },
            .severity = .error_sev,
            .message = "Schema has parse errors",
        }) catch {};
    }

    // Stage 2: Semantic analysis with diagnostic capture
    var collector = diag_mod.DiagnosticCollector.init(alloc) catch {
        return .{ .diagnostics = try diagnostics.toOwnedSlice(alloc) };
    };

    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = sa.analyzeWithCollector(tree, &collector);

    // Convert captured diagnostics to LSP format
    for (collector.diagnostics.items) |d| {
        const severity: DiagnosticSeverity = switch (d.severity) {
            .@"error" => .error_sev,
            .warning => .warning,
            .note => .information,
        };
        const line: u32 = if (d.line_no > 0) @intCast(d.line_no - 1) else 0;
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

test "compile valid schema" {
    const result = compile(std.testing.allocator,
        \\# users table
        \\table users {
        \\  id    n   ++ PK
        \\  name  s64
        \\}
    , "test.ss", .mysql);
    defer std.testing.allocator.free(result.diagnostics);

    // Valid schema should have no errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false); // Should not have errors
        }
    }
}

test "compile invalid schema" {
    const result = compile(std.testing.allocator,
        \\table { }
    , "test.ss", .mysql);
    defer std.testing.allocator.free(result.diagnostics);

    // Invalid schema should have at least one diagnostic
    try std.testing.expect(result.diagnostics.len > 0);
}

test "compile empty schema" {
    const result = compile(std.testing.allocator, "", "test.ss", .mysql);
    defer std.testing.allocator.free(result.diagnostics);

    // Empty schema should compile without errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false);
        }
    }
}

test "compile schema with foreign key" {
    const result = compile(std.testing.allocator,
        \\table users {
        \\  id n ++ PK
        \\}
        \\
        \\table posts {
        \\  id      n  ++ PK
        \\  user_id n  -> users.id
        \\}
    , "test.ss", .mysql);
    defer std.testing.allocator.free(result.diagnostics);

    // Valid schema with FK should have no errors
    for (result.diagnostics) |d| {
        if (d.severity == .error_sev) {
            try std.testing.expect(false);
        }
    }
}
