const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const lint_mod = @import("../lint.zig");
const common = @import("common.zig");

// ─── WASM Lint Exports ──────────────────────────────────────────
// Lint functions for schema quality checking.

/// Lint a Rune schema and return results as text.
pub export fn rune_lint(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const as_json = common.parseOption(options, "format") != null and std.mem.eql(u8, common.parseOption(options, "format").?, "json");

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Run lint
    const cfg = lint_mod.LintConfig{};
    const results = lint_mod.lintSchema(alloc, result.resolved, cfg) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Format output
    const output = if (as_json)
        lint_mod.formatLintJson(alloc, results.items) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        }
    else
        lint_mod.formatLintResults(alloc, results.items, false) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_lint basic" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_lint(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_lint invalid schema" {
    const schema = "this is not valid ss";
    const result = rune_lint(schema.ptr, schema.len, "", 0);
    // Parser is lenient — invalid input produces warnings but compiles.
    // Just verify the function doesn't crash.
    _ = result;
    @import("error.zig").rune_reset();
}

test "rune_lint JSON format" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_lint(schema.ptr, schema.len, "format=json", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        // JSON output should start with { or [
        try std.testing.expect(output[0] == '{' or output[0] == '[');
    }
    @import("error.zig").rune_reset();
}

test "rune_lint dialect option" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_lint(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}
