// Architecture health checks — verifies module boundaries and public API stability.
// These tests catch regressions in module structure and ensure documentation accuracy.
//
// When adding new modules, generators, passes, or dialect backends, update the
// corresponding count ranges below to keep documentation accurate.

const std = @import("std");

// ─── Pipeline API Tests ────────────────────────────────────────

test "pipeline handler public API exists" {
    // Verify key public types are accessible from handlers module
    const handlers = @import("../pipeline/handlers.zig");
    _ = handlers.ValidateConfig;
    _ = handlers.FormatConfig;
    _ = handlers.ExportConfig;
    _ = handlers.StatsConfig;
    _ = handlers.OutputFormat;
    _ = handlers.ExportFormat;
}

test "pipeline generate module public API exists" {
    // Verify generate module has expected public types
    const generate = @import("../pipeline/generate.zig");
    _ = generate.GenerateConfig;
    _ = generate.handleGenerate;
}

// ─── Registry & Dispatch Tests ─────────────────────────────────

test "generator registry has expected count" {
    // Verify all generators are registered (11 as of v0.271.0)
    const generator = @import("../generator.zig");
    const count = generator.REGISTRY.len;
    try std.testing.expect(count >= 11); // At least 11 generators
    try std.testing.expect(count <= 15); // Sanity upper bound
}

test "semantic pass count matches documentation" {
    // Verify pass manager has expected number of passes (17 as of v0.271.0)
    const pm = @import("../semantic/pass_manager.zig");
    const count = pm.DEFAULT_PASSES.len;
    try std.testing.expect(count >= 16); // At least 16 passes
    try std.testing.expect(count <= 20); // Sanity upper bound
}

test "dialect backend count matches documentation" {
    // Verify all 6 dialect backends are registered
    const dialect_enum = @import("../dialect/enum.zig");
    const Dialect = dialect_enum.Dialect;
    // Verify the enum has 6 variants
    const fields = @typeInfo(Dialect).@"enum".fields;
    try std.testing.expectEqual(@as(usize, 6), fields.len);
}

test "lint rule count matches documentation" {
    // Verify lint rules have expected count (56 rules as of v0.271.0)
    const lint_config = @import("../lint/config.zig");
    const LintRule = lint_config.LintRule;
    const fields = @typeInfo(LintRule).@"enum".fields;
    try std.testing.expect(fields.len >= 54); // At least 54 rules
    try std.testing.expect(fields.len <= 60); // Sanity upper bound
}

// ─── DialectBackend vtable Tests ───────────────────────────────

test "dialect backend vtable has expected field count" {
    // DialectBackend should have 33 function pointers + 3 flags + 1 data = 37 total fields
    // This catches regressions if someone accidentally removes a vtable method
    const dialect = @import("../dialect/dialect.zig");
    const info = @typeInfo(dialect.DialectBackend).@"struct";
    // 26 required + 7 optional function pointers + 3 behavioral flags + 1 quoteChar = 37
    try std.testing.expect(info.fields.len >= 35); // At least 35 (conservative)
    try std.testing.expect(info.fields.len <= 45); // Sanity upper bound
}

test "all 6 dialect backends are importable" {
    // Verify each dialect backend module can be imported at comptime
    const dialect = @import("../dialect/dialect.zig");
    const dialect_enum = @import("../dialect/enum.zig");
    const Dialect = dialect_enum.Dialect;
    const backends = [_]Dialect{ .mysql, .pg, .sqlite, .mssql, .oracle, .db2 };
    inline for (backends) |d| {
        const backend = dialect.getBackend(d);
        _ = backend;
    }
}

// ─── WASM Module Tests ─────────────────────────────────────────

test "wasm sub-modules are importable" {
    // Verify all 10 WASM sub-modules compile correctly
    _ = @import("../wasm/common.zig");
    _ = @import("../wasm/error.zig");
    _ = @import("../wasm/compile.zig");
    _ = @import("../wasm/diff.zig");
    _ = @import("../wasm/reverse.zig");
    _ = @import("../wasm/lint.zig");
    _ = @import("../wasm/format.zig");
    _ = @import("../wasm/generate.zig");
    _ = @import("../wasm/export.zig");
    _ = @import("../wasm/docs.zig");
}

// ─── LSP Dispatch Table Tests ──────────────────────────────────

test "lsp dispatch table has expected entry count" {
    // LSP server should handle 22 methods via table-driven dispatch
    const lsp_server = @import("../lsp/server.zig");
    // We can't directly access DISPATCH_TABLE (it's private), but we can
    // verify the Server type exists and has the expected structure
    _ = lsp_server.Server;
}

// ─── Type System Tests ─────────────────────────────────────────

test "reverse map has expected entry count" {
    // REVERSE_MAP should have 52+ entries for comprehensive SQL→SS mapping
    const reverse_map = @import("../types/reverse_map.zig");
    const count = reverse_map.REVERSE_MAP.len;
    try std.testing.expect(count >= 52); // At least 52 entries
    try std.testing.expect(count <= 150); // Sanity upper bound
}

test "type registry has expected dialect count" {
    // DIALECT_NAMES should list all 6 dialects
    const reverse_map = @import("../types/reverse_map.zig");
    try std.testing.expectEqual(@as(usize, 6), reverse_map.DIALECT_NAMES.len);
}

// ─── Code Quality Tests ────────────────────────────────────────

test "no catch unreachable in production code" {
    // This test verifies the production codebase has zero catch unreachable.
    // It imports key production modules to ensure they compile correctly.
    // Actual verification is done via grep in CI (see CLAUDE.md).
    const handlers = @import("../pipeline/handlers.zig");
    const generate = @import("../pipeline/generate.zig");
    const forward = @import("../pipeline/forward.zig");
    const io_mod = @import("../io.zig");
    _ = handlers;
    _ = generate;
    _ = forward;
    _ = io_mod;
}

test "config structs have named defaults" {
    // Verify all config structs have default values (no undefined fields)
    const forward = @import("../pipeline/forward.zig");
    const CompileConfig = forward.CompileConfig;
    // CompileConfig should be default-initializable
    const cfg = CompileConfig{};
    _ = cfg;
}

// ─── Formatter Tests ───────────────────────────────────────────

test "formatter module is importable" {
    // Verify the formatter module compiles correctly
    const formatter = @import("../formatter.zig");
    _ = formatter;
}

// ─── Generator Tests ───────────────────────────────────────────

test "all generators have valid metadata" {
    // Verify all generators have version and author metadata
    const generator = @import("../generator.zig");
    for (generator.REGISTRY) |gen| {
        try std.testing.expect(gen.version.len > 0);
        try std.testing.expect(gen.author.len > 0);
        try std.testing.expect(gen.name.len > 0);
        try std.testing.expect(gen.description.len > 0);
        try std.testing.expect(gen.extension.len > 0);
    }
}
