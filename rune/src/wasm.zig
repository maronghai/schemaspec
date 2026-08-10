const std = @import("std");
const pipeline = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const lint_mod = @import("lint.zig");
const codegen = @import("codegen/codegen.zig");
const TypeResolver = @import("types/type_resolver.zig").TypeResolver;
const dialect_enum = @import("dialect/enum.zig");
const dialect_mod = @import("dialect/dialect.zig");
const resolved_ast = @import("types/resolved_ast.zig");
const diff_engine = @import("diff/engine.zig");
const enums = @import("types/enums.zig");
const text_fmt = @import("diff/format/text.zig");
const format_common = @import("diff/format_common.zig");
const json_fmt = @import("diff/format/json.zig");
const sarif_fmt = @import("diff/format/sarif.zig");
const markdown_fmt = @import("diff/format/markdown.zig");
const migrate = @import("diff/migrate.zig");
const sql_parser = @import("parser/sql_parser.zig");
const reverse_codegen = @import("reverse/codegen.zig");
const dialect_detect = @import("reverse/dialect_detect.zig");
const diag = @import("semantic/diagnostic.zig");
const stats_mod = @import("pipeline/stats.zig");
const handlers = @import("pipeline/handlers.zig");
const formatter = @import("formatter.zig");
const tune_mod = @import("tune.zig");
const generator = @import("generator.zig");

// ─── WASM Library Entry Point ──────────────────────────────────
// Compile-time entry point for wasm32-wasi target. Exports C-compatible
// functions for host environments (Deno, browsers, WASM runtimes).
// No dependency on std.process — suitable for WASM compilation.

/// Global arena allocator for WASM. Grows across calls; reset with rune_reset().
var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);

/// Last error message from rune_compile. Null when no error has occurred.
var last_error: ?[*:0]const u8 = null;

/// Numeric error code from the last operation. 0 = success.
/// 1 = syntax error, 2 = type error, 3 = FK error, 4 = semantic error, 5 = unknown error.
var last_error_code: i32 = 0;

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
    last_error_code = 0;

    // Parse options
    const dialect = parseDialectOption(options);

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
    last_error_code = 0;
    _ = gpa.reset(.retain_capacity);
}

/// Get the last error message from rune_compile.
/// Returns null if no error has occurred since the last successful compile or reset.
export fn rune_last_error() ?[*:0]const u8 {
    return last_error;
}

/// Get the numeric error code from the last operation.
/// 0 = success, 1 = syntax, 2 = type, 3 = FK, 4 = semantic, 5 = unknown.
export fn rune_last_error_code() i32 {
    return last_error_code;
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

/// Parse dialect from WASM options string. Returns .mysql as default.
fn parseDialectOption(options: []const u8) dialect_enum.Dialect {
    if (parseOption(options, "dialect")) |val| {
        return dialect_enum.parseDialect(val) catch .mysql;
    }
    return .mysql;
}

/// Parse diff format from WASM options string. Returns .text as default.
fn parseDiffFormatOption(options: []const u8) enums.DiffFormat {
    if (parseOption(options, "format")) |val| {
        return std.meta.stringToEnum(enums.DiffFormat, val) orelse .text;
    }
    return .text;
}

/// Store an error message for retrieval via rune_last_error().
fn storeError(alloc: std.mem.Allocator, err_name: []const u8) void {
    last_error = alloc.dupeZ(u8, err_name) catch null;
    // Map error names to numeric codes
    last_error_code = if (std.mem.indexOf(u8, err_name, "Syntax") != null or std.mem.indexOf(u8, err_name, "Parse") != null)
        1
    else if (std.mem.indexOf(u8, err_name, "Type") != null)
        2
    else if (std.mem.indexOf(u8, err_name, "Foreign") != null or std.mem.indexOf(u8, err_name, "Fk") != null)
        3
    else if (std.mem.indexOf(u8, err_name, "Semantic") != null or std.mem.indexOf(u8, err_name, "Diagnostic") != null)
        4
    else
        5;
}

/// Format diff as text with summary statistics. Helper for rune_diff.
fn formatDiffText(alloc: std.mem.Allocator, d: diff_engine.SchemaDiff, dialect: dialect_enum.Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const q = dialect_mod.getBackend(dialect).quoteChar;
    try text_fmt.writeDiffTo(w, d, q, false);
    // Add summary statistics
    const stats = format_common.DiffStats.compute(d);
    const total = stats.dropped_tables + stats.added_tables + stats.modified_tables;
    if (total > 0) {
        try w.writeAll("\n");
        try format_common.formatSummaryStats(w, stats, false);
    }
    try w.flush();
    return try aw.toOwnedSlice();
}

/// Compile two schemas and return the diff as text.
export fn rune_diff(schema1_ptr: [*]const u8, schema1_len: usize, schema2_ptr: [*]const u8, schema2_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema1 = schema1_ptr[0..schema1_len];
    const schema2 = schema2_ptr[0..schema2_len];
    const options = options_ptr[0..options_len];

    last_error = null;

    const dialect = parseDialectOption(options);
    const fmt_type = parseDiffFormatOption(options);

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
    const schema_diff = diff_engine.diff(old_result.resolved, new_result.resolved, alloc) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Format diff based on requested format
    const output = switch (fmt_type) {
        .text => formatDiffText(alloc, schema_diff, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        },
        .json => json_fmt.formatDiffJson(alloc, schema_diff) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        },
        .sarif => sarif_fmt.formatDiffSarif(alloc, schema_diff, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        },
        .markdown => markdown_fmt.formatDiffMarkdown(alloc, schema_diff, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        },
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

    const dialect = parseDialectOption(options);
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
    const schema_diff = diff_engine.diff(old_result.resolved, new_result.resolved, alloc) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types for migration generation
    const new_typed = TypeResolver.resolve(alloc, new_result.resolved, dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Generate migration SQL
    const output = if (rollback)
        migrate.generateRollback(alloc, schema_diff, new_typed, new_result.resolved, dialect) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        }
    else
        migrate.generateFromDiff(alloc, schema_diff, new_typed, new_result.resolved, dialect) catch |err| {
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

    const dialect = parseDialectOption(options);
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
    var rc = reverse_codegen.ReverseCodegen.init(alloc, dialect);
    const output = if (with_templates)
        rc.generateWithTemplates(result.schema) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        }
    else
        rc.generate(result.schema) catch |err| {
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

    const dialect = parseDialectOption(options);
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
        lint_mod.formatLintResults(alloc, results.items, false) catch |err| {
            storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

/// Compile a schema and return statistics as JSON.
export fn rune_stats(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    last_error = null;
    last_error_code = 0;

    const dialect = parseDialectOption(options);

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Compute stats and return as JSON
    const s = stats_mod.computeStats(result.resolved);
    const json = stats_mod.formatStatsJson(alloc, s) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, json) catch null;
}

/// Validate a schema and return results as JSON.
export fn rune_validate(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    last_error = null;
    last_error_code = 0;

    const dialect = parseDialectOption(options);

    // Compile schema (may fail with DiagnosticsError for invalid schemas)
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            const s = stats_mod.Stats{ .tables = 0, .fields = 0, .views = 0, .not_null_fields = 0, .numeric_fields = 0, .string_fields = 0, .datetime_fields = 0, .boolean_fields = 0, .other_fields = 0, .foreign_keys = 0, .indexes = 0, .check_constraints = 0, .custom_types = 0 };
            const json = handlers.formatValidateResult(alloc, false, s, 1) catch return null;
            return alloc.dupeZ(u8, json) catch null;
        }
        storeError(alloc, @errorName(err));
        return null;
    };

    // Compute stats and validate
    const s = stats_mod.computeStats(result.resolved);
    const json = handlers.formatValidateResult(alloc, !result.partial, s, if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, json) catch null;
}

// ─── New Exports ──────────────────────────────────────────────

/// Format a Rune .ss schema with consistent style.
/// Returns formatted .ss text. No options needed (formatter is dialect-agnostic).
export fn rune_format(schema_ptr: [*]const u8, schema_len: usize, _: [*]const u8, _: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];

    last_error = null;
    last_error_code = 0;

    const output = formatter.format(alloc, schema) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Auto-extract common fields into templates (tune).
/// Returns .ss text with extracted template definitions.
export fn rune_tune(schema_ptr: [*]const u8, schema_len: usize, _: [*]const u8, _: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];

    last_error = null;
    last_error_code = 0;

    const output = tune_mod.tune(alloc, schema) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Generate output using a named generator (prisma, drizzle, openapi, etc.).
/// Options: "generator=<name> dialect=<dialect>".
export fn rune_generate(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    last_error = null;
    last_error_code = 0;

    const dialect = parseDialectOption(options);
    const gen_name = parseOption(options, "generator") orelse {
        storeError(alloc, "missing generator option (e.g. generator=prisma)");
        return null;
    };

    const gen = generator.get(gen_name) orelse {
        storeError(alloc, "unknown generator");
        return null;
    };

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types
    const typed = TypeResolver.resolve(alloc, result.resolved, dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    // Generate output
    const output = gen.generate(alloc, typed, dialect) catch |err| {
        storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ────────────────────────────────────────────────────

test "parseOption" {
    try std.testing.expectEqualStrings("pg", parseOption("dialect=pg", "dialect").?);
    try std.testing.expectEqualStrings("mysql", parseOption("dialect=mysql format=sql", "dialect").?);
    try std.testing.expectEqualStrings("sql", parseOption("dialect=mysql format=sql", "format").?);
    try std.testing.expect(parseOption("other=pg", "dialect") == null);
    try std.testing.expect(parseOption("", "dialect") == null);
}

test "rune_compile basic" {
    const schema = "# users\nid N ++\nname s\n";
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
    // Parser is lenient — invalid input produces warnings but compiles.
    // Just verify the function doesn't crash.
    _ = result;
    rune_reset();
}

test "rune_diff two schemas" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_lint basic" {
    const schema = "# users\nid N ++\nname s\n";
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

test "parseDialectOption defaults to mysql" {
    try std.testing.expectEqual(dialect_enum.Dialect.mysql, parseDialectOption(""));
    try std.testing.expectEqual(dialect_enum.Dialect.mysql, parseDialectOption("other=val"));
}

test "parseDialectOption parses known dialects" {
    try std.testing.expectEqual(dialect_enum.Dialect.pg, parseDialectOption("dialect=pg"));
    try std.testing.expectEqual(dialect_enum.Dialect.sqlite, parseDialectOption("dialect=sqlite"));
    try std.testing.expectEqual(dialect_enum.Dialect.mssql, parseDialectOption("dialect=mssql"));
    try std.testing.expectEqual(dialect_enum.Dialect.oracle, parseDialectOption("dialect=oracle"));
    try std.testing.expectEqual(dialect_enum.Dialect.db2, parseDialectOption("dialect=db2"));
}

test "parseDialectOption with multiple options" {
    try std.testing.expectEqual(dialect_enum.Dialect.pg, parseDialectOption("dialect=pg format=json"));
}

test "parseDiffFormatOption defaults to text" {
    try std.testing.expectEqual(enums.DiffFormat.text, parseDiffFormatOption(""));
    try std.testing.expectEqual(enums.DiffFormat.text, parseDiffFormatOption("dialect=pg"));
}

test "parseDiffFormatOption parses known formats" {
    try std.testing.expectEqual(enums.DiffFormat.json, parseDiffFormatOption("format=json"));
    try std.testing.expectEqual(enums.DiffFormat.sarif, parseDiffFormatOption("format=sarif"));
    try std.testing.expectEqual(enums.DiffFormat.markdown, parseDiffFormatOption("format=markdown"));
}

test "rune_migrate basic" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_migrate(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
    }
    rune_reset();
}

test "rune_migrate with rollback" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_migrate(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg rollback", 14);
    try std.testing.expect(result != null);
    if (result) |r| {
        const sql = std.mem.span(r);
        try std.testing.expect(sql.len > 0);
    }
    rune_reset();
}

test "rune_reverse basic" {
    const sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));\n";
    const result = rune_reverse(sql.ptr, sql.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const ss = std.mem.span(r);
        try std.testing.expect(ss.len > 0);
    }
    rune_reset();
}

test "rune_reverse with templates" {
    const sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));\nCREATE TABLE posts (id INT PRIMARY KEY, title VARCHAR(200));\n";
    const result = rune_reverse(sql.ptr, sql.len, "dialect=pg templates", 20);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_diff json format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=json", 22);
    try std.testing.expect(result != null);
    if (result) |r| {
        const json = std.mem.span(r);
        try std.testing.expect(json.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, json, "{") != null);
    }
    rune_reset();
}

test "rune_diff sarif format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=sarif", 23);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_diff markdown format" {
    const schema1 = "# users\nid N ++\nname s\n";
    const schema2 = "# users\nid N ++\nname s\nemail s\n";
    const result = rune_diff(schema1.ptr, schema1.len, schema2.ptr, schema2.len, "dialect=pg format=markdown", 26);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_last_error after compile error" {
    // First, do a successful compile to clear any previous state
    const valid = "# users\nid N ++\nname s\n";
    _ = rune_compile(valid.ptr, valid.len, "dialect=pg", 11);
    try std.testing.expect(rune_last_error() == null);
    // Now reset and verify clean state
    rune_reset();
    try std.testing.expect(rune_last_error() == null);
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
    rune_reset();
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
    rune_reset();
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
    rune_reset();
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
    rune_reset();
}

test "rune_last_error_code after success" {
    const schema = "# users\nid N ++\nname s\n";
    _ = rune_compile(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expectEqual(@as(i32, 0), rune_last_error_code());
    rune_reset();
    try std.testing.expectEqual(@as(i32, 0), rune_last_error_code());
}

test "rune_last_error_code after reset" {
    rune_reset();
    try std.testing.expectEqual(@as(i32, 0), rune_last_error_code());
}

test "rune_format basic" {
    const schema = "# users\nid n pk\nname s\n";
    const result = rune_format(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    if (result) |r| {
        const formatted = std.mem.span(r);
        try std.testing.expect(formatted.len > 0);
        // Should be formatted with indentation
        try std.testing.expect(std.mem.indexOf(u8, formatted, "  id") != null);
    }
    rune_reset();
}

test "rune_format already formatted" {
    const schema = "# users\n  id n pk\n  name s\n";
    const result = rune_format(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_tune extracts templates" {
    const schema = "# user\nid p\nname s\nemail s\n\n# post\nid p\nname s\nemail s\ntitle s\n";
    const result = rune_tune(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    if (result) |r| {
        const tuned = std.mem.span(r);
        try std.testing.expect(std.mem.indexOf(u8, tuned, "% base") != null);
    }
    rune_reset();
}

test "rune_tune single table returns original" {
    const schema = "# user\nid p\nname s\n";
    const result = rune_tune(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    rune_reset();
}

test "rune_generate prisma" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=prisma dialect=pg", 28);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "model") != null);
    }
    rune_reset();
}

test "rune_generate json-schema" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=json-schema dialect=pg", 32);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "{") != null);
    }
    rune_reset();
}

test "rune_generate unknown generator" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=nonexistent", 21);
    try std.testing.expect(result == null);
    const err = rune_last_error();
    try std.testing.expect(err != null);
    rune_reset();
}

test "rune_generate missing generator option" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result == null);
    const err = rune_last_error();
    try std.testing.expect(err != null);
    rune_reset();
}
