const std = @import("std");
const pipeline = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const lint_mod = @import("lint.zig");
const codegen = @import("codegen/codegen.zig");
const TypeResolver = @import("types/type_resolver.zig").TypeResolver;
const dialect_enum = @import("dialect/enum.zig");
const resolved_ast = @import("types/resolved_ast.zig");
const diff_engine = @import("diff/engine.zig");
const diff_types = @import("diff/types.zig");
const diff_format = @import("diff/format.zig");
const migrate = @import("diff/migrate.zig");
const sql_parser = @import("parser/sql_parser.zig");
const reverse_codegen = @import("reverse/codegen.zig");
const dialect_detect = @import("reverse/dialect_detect.zig");
const diag = @import("semantic/diagnostic.zig");

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

/// Compile two schemas and return the diff as text.
export fn rune_diff(schema1_ptr: [*]const u8, schema1_len: usize, schema2_ptr: [*]const u8, schema2_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema1 = schema1_ptr[0..schema1_len];
    const schema2 = schema2_ptr[0..schema2_len];
    const options = options_ptr[0..options_len];

    last_error = null;

    var dialect: dialect_enum.Dialect = .mysql;
    if (parseOption(options, "dialect")) |val| {
        dialect = dialect_enum.parseDialect(val) catch .mysql;
    }
    const fmt_type: diff_types.DiffFormat = if (parseOption(options, "format")) |val|
        std.meta.stringToEnum(diff_types.DiffFormat, val) catch .text
    else
        .text;

    // Compile both schemas
    const old_result = pipeline.compilePipeline(alloc, schema1, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };
    const new_result = pipeline.compilePipeline(alloc, schema2, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Compute diff
    const schema_diff = diff_engine.computeDiff(alloc, old_result.resolved, new_result.resolved) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Format diff
    const output = diff_format.formatDiff(alloc, schema_diff, fmt_type, dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Compile two schemas and return migration SQL.
export fn rune_migrate(schema1_ptr: [*]const u8, schema1_len: usize, schema2_ptr: [*]const u8, schema2_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema1 = schema1_ptr[0..schema1_len];
    const schema2 = schema2_ptr[0..schema2_len];
    const options = options_ptr[0..options_len];

    last_error = null;

    var dialect: dialect_enum.Dialect = .mysql;
    if (parseOption(options, "dialect")) |val| {
        dialect = dialect_enum.parseDialect(val) catch .mysql;
    }
    const rollback = parseOption(options, "rollback") != null;

    // Compile both schemas
    const old_result = pipeline.compilePipeline(alloc, schema1, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };
    const new_result = pipeline.compilePipeline(alloc, schema2, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Compute diff
    const schema_diff = diff_engine.computeDiff(alloc, old_result.resolved, new_result.resolved) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Generate migration SQL
    const output = if (rollback)
        migrate.generateRollback(alloc, schema_diff, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        }
    else
        migrate.generateFromDiff(alloc, schema_diff, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

/// Reverse-engineer SQL DDL to Rune .ss schema.
export fn rune_reverse(sql_ptr: [*]const u8, sql_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const sql = sql_ptr[0..sql_len];
    const options = options_ptr[0..options_len];

    last_error = null;

    var dialect: dialect_enum.Dialect = .mysql;
    if (parseOption(options, "dialect")) |val| {
        dialect = dialect_enum.parseDialect(val) catch .mysql;
    }
    const with_templates = parseOption(options, "templates") != null;

    // Auto-detect dialect if not specified
    const sql_dialect: sql_parser.Dialect = if (dialect == .mysql) dialect_detect.detectSqlDialect(sql) else dialect;

    // Parse SQL
    var sp_parser = sql_parser.SqlParser.init(alloc, sql, sql_dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };
    const result = sp_parser.parse() catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Reverse-engineer to .ss
    const output = reverse_codegen.reverseSchema(alloc, result.schema, .{
        .dialect = dialect,
        .with_templates = with_templates,
    }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Lint a Rune schema and return results as text.
export fn rune_lint(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    last_error = null;

    var dialect: dialect_enum.Dialect = .mysql;
    if (parseOption(options, "dialect")) |val| {
        dialect = dialect_enum.parseDialect(val) catch .mysql;
    }
    const as_json = parseOption(options, "format") != null and std.mem.eql(u8, parseOption(options, "format").?, "json");

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Run lint
    const cfg = lint_mod.LintConfig{};
    const results = lint_mod.lintSchema(alloc, result.resolved, cfg) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Format output
    const output = if (as_json)
        lint_mod.formatLintJson(alloc, results.items) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        }
    else
        lint_mod.formatLintResults(alloc, results.items) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

test "parseOption" {
    try std.testing.expectEqualStrings("pg", parseOption("dialect=pg", "dialect").?);
    try std.testing.expectEqualStrings("mysql", parseOption("dialect=mysql format=sql", "dialect").?);
    try std.testing.expectEqualStrings("sql", parseOption("dialect=mysql format=sql", "format").?);
    try std.testing.expect(parseOption("other=pg", "dialect") == null);
    try std.testing.expect(parseOption("", "dialect") == null);
}

test "rune_compile basic" {
    const schema = "t users {\n  id n pk\n  name s\n}\n";
    const result = rune_compile(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE") != null);
    }
    rune_reset();
}

test "rune_compile invalid schema" {
    const schema = "this is not valid ss";
    const result = rune_compile(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result == null);
    rune_reset();
}

test "rune_diff two schemas" {
    const schema1 = "t users {\n  id n pk\n  name s\n}\n";
    const schema2 = "t users {\n  id n pk\n  name s\n  email s\n}\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_lint basic" {
    const schema = "t users {\n  id n pk\n  name s\n}\n";
    const result = rune_lint(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_version returns version" {
    const ver = rune_version();
    try std.testing.expect(ver != null);
    if (ver) |v| {
        const version_str = std.mem.span(v);
        try std.testing.expect(version_str.len > 0);
    }
    rune_reset();
}
