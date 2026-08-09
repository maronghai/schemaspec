const std = @import("std");
const pipeline = @import("pipeline/forward.zig");
const codegen = @import("codegen/codegen.zig");
const TypeResolver = @import("types/type_resolver.zig").TypeResolver;
const dialect_enum = @import("dialect/enum.zig");

// ─── WASM Library Entry Point ──────────────────────────────────
// Compile-time entry point for wasm32-wasi target. Exports C-compatible
// functions for host environments (Deno, browsers, WASM runtimes).
// No dependency on std.process — suitable for WASM compilation.

/// Global arena allocator for WASM. Grows across calls; reset with rune_reset().
var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);

/// Last error message from rune_compile. Null when no error has occurred.
var last_error: ?[*:0]const u8 = null;

/// Compile a Rune schema and return the generated SQL.
/// `schema_ptr`/`schema_len`: UTF-8 schema text (.ss file content).
/// `options_ptr`/`options_len`: UTF-8 options string (e.g. "dialect=pg").
/// Returns a pointer to a null-terminated result string.
/// Caller must copy the result before the next compile or reset call.
/// On error, returns null — call rune_last_error() for details.
export fn rune_compile(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    // Clear previous error
    last_error = null;

    // Parse options: "dialect=pg" format
    var dialect: dialect_enum.Dialect = .mysql;
    if (parseOption(options, "dialect")) |val| {
        dialect = dialect_enum.parseDialect(val) catch .mysql;
    }

    // Compile schema through the forward pipeline
    const result = pipeline.compilePipeline(alloc, schema, .{
        .dialect = dialect,
        .run_semantic = true,
    }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types (ResolvedAst → TypedAst)
    const typed = TypeResolver.resolve(alloc, result.resolved, dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Generate SQL from TypedAst
    var cg = codegen.Codegen.init(alloc, dialect);
    const sql = cg.generateFromTypedAst(typed) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Return as null-terminated string
    return alloc.dupeZ(u8, sql) catch null;
}

/// Free all memory allocated by rune_compile.
export fn rune_reset() void {
    last_error = null;
    _ = gpa.reset(.retain_capacity);
}

/// Get the last error message from rune_compile.
/// Returns null if no error has occurred since the last successful compile or reset.
export fn rune_last_error() ?[*:0]const u8 {
    return last_error;
}

/// Get the Rune version string.
export fn rune_version() ?[*:0]const u8 {
    const alloc = gpa.allocator();
    return alloc.dupeZ(u8, @import("version.zig").VERSION) catch null;
}

/// Parse "key=value" from a space-separated options string.
fn parseOption(options: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, options, ' ');
    while (iter.next()) |token| {
        if (std.mem.indexOfScalar(u8, token, '=')) |eq| {
            if (std.mem.eql(u8, token[0..eq], key)) {
                return token[eq + 1 ..];
            }
        }
    }
    return null;
}

/// Store an error message for retrieval via rune_last_error().
fn storeError(alloc: std.mem.Allocator, err_name: []const u8) void {
    last_error = alloc.dupeZ(u8, err_name) catch null;
}

test "parseOption" {
    try std.testing.expectEqualStrings("pg", parseOption("dialect=pg", "dialect").?);
    try std.testing.expectEqualStrings("mysql", parseOption("dialect=mysql format=sql", "dialect").?);
    try std.testing.expectEqualStrings("sql", parseOption("dialect=mysql format=sql", "format").?);
    try std.testing.expect(parseOption("other=pg", "dialect") == null);
    try std.testing.expect(parseOption("", "dialect") == null);
}
