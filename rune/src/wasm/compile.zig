const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const codegen = @import("../codegen/codegen.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const stats_mod = @import("../pipeline/stats.zig");
const handlers = @import("../pipeline/handlers.zig");
const common = @import("common.zig");

// ─── WASM Compile Exports ───────────────────────────────────────
// Compilation, stats, and validation functions.

/// Compile a Rune schema and return the generated SQL.
/// `schema_ptr`/`schema_len`: UTF-8 schema text (.ss file content).
/// `options_ptr`/`options_len`: UTF-8 options string (e.g. "dialect=pg").
/// Returns a pointer to a null-terminated result string.
/// Caller must copy the result before the next compile or reset call.
/// On error, returns null — call rune_last_error() for details.
pub export fn rune_compile(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    // Clear previous error
    common.clearError();

    // Parse options
    const dialect = common.parseDialectOption(options);

    // Compile schema through the forward pipeline
    const result = pipeline.compilePipeline(alloc, schema, .{
        .dialect = dialect,
        .run_semantic = true,
    }) catch |err| {
        if (err == error.SemanticError) {
            // Semantic diagnostics were silenced (no stderr on wasm) — surface
            // them via the validate JSON report instead.
            if (rune_validate(schema_ptr, schema_len, options_ptr, options_len)) |report| {
                common.storeError(alloc, std.mem.span(report));
            } else {
                common.storeError(alloc, @errorName(err));
            }
            return null;
        }
        common.storeError(alloc, @errorName(err));
        return null;
    };
    if (result.partial) {
        common.storeError(alloc, "schema has parse errors — see rune validate for details");
        return null;
    }

    // Resolve types (ResolvedAst → TypedAst)
    const typed = TypeResolver.resolve(alloc, result.resolved, dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Generate SQL from TypedAst
    var cg = codegen.Codegen.init(alloc, dialect);
    const sql = cg.generateFromTypedAst(typed) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Return as null-terminated string
    return alloc.dupeZ(u8, sql) catch null;
}

/// Compile a schema and return statistics as JSON.
pub export fn rune_stats(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Compute stats and return as JSON
    const s = stats_mod.computeStats(result.resolved);
    const json = stats_mod.formatStatsJson(alloc, s) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, json) catch null;
}

/// Validate a schema and return results as JSON.
pub export fn rune_validate(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);

    // Compile schema (may fail with DiagnosticsError for invalid schemas)
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            const s = stats_mod.Stats{ .tables = 0, .fields = 0, .views = 0, .not_null_fields = 0, .numeric_fields = 0, .string_fields = 0, .datetime_fields = 0, .boolean_fields = 0, .other_fields = 0, .foreign_keys = 0, .indexes = 0, .check_constraints = 0, .custom_types = 0 };
            const json = handlers.formatValidateResult(alloc, false, s, 1) catch return null;
            return alloc.dupeZ(u8, json) catch null;
        }
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Compute stats and validate
    const s = stats_mod.computeStats(result.resolved);
    const json = handlers.formatValidateResult(alloc, !result.partial, s, if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, json) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_compile basic" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_compile(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_compile invalid schema" {
    const schema = "this is not valid ss";
    const result = rune_compile(schema.ptr, schema.len, "", 0);
    // Parser is lenient — invalid input produces warnings but compiles.
    // Just verify the function doesn't crash.
    _ = result;
    @import("error.zig").rune_reset();
}

test "rune_stats basic" {
    const schema = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_stats(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        // Should contain expected fields
        try std.testing.expect(std.mem.indexOf(u8, json, "\"tables\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, json, "\"fields\"") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_stats empty schema" {
    const schema = "";
    const result = rune_stats(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        // Empty schema should have 0 tables
        try std.testing.expect(std.mem.indexOf(u8, json, "\"tables\":0") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_validate valid schema" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_validate(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        // Should be valid
        try std.testing.expect(std.mem.indexOf(u8, json, "\"valid\":true") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_validate with per-table stats" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_validate(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        // Should contain tables count
        try std.testing.expect(std.mem.indexOf(u8, json, "\"tables\"") != null);
    }
    @import("error.zig").rune_reset();
}
