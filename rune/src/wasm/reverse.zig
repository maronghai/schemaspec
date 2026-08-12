const std = @import("std");
const sql_parser = @import("../parser/sql_parser.zig");
const reverse_codegen = @import("../reverse/codegen.zig");
const dialect_detect = @import("../reverse/dialect_detect.zig");
const common = @import("common.zig");

// ─── WASM Reverse Exports ───────────────────────────────────────
// Reverse engineering functions.

/// Reverse-engineer SQL DDL to Rune .ss schema.
pub export fn rune_reverse(sql_ptr: [*]const u8, sql_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const sql = sql_ptr[0..sql_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const with_templates = common.parseOption(options, "templates") != null;

    // Auto-detect dialect if not specified
    const sql_dialect: sql_parser.Dialect = if (dialect == .mysql) dialect_detect.detectSqlDialect(sql) else dialect;

    // Parse SQL
    var sp_parser = sql_parser.SqlParser.init(alloc, sql, sql_dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };
    const result = sp_parser.parse() catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Reverse-engineer to .ss
    var rc = reverse_codegen.ReverseCodegen.init(alloc, dialect);
    const output = if (with_templates)
        rc.generateWithTemplates(result.schema) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        }
    else
        rc.generate(result.schema) catch |err| {
            common.storeError(alloc, @errorName(err));
            return null;
        };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_reverse basic" {
    const sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));\n";
    const result = rune_reverse(sql.ptr, sql.len, "dialect=pg", 11);
    try std.testing.expect(result != null);
    if (result) |r| {
        const ss = std.mem.span(r);
        try std.testing.expect(ss.len > 0);
    }
    @import("error.zig").rune_reset();
}

test "rune_reverse with templates" {
    const sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));\nCREATE TABLE posts (id INT PRIMARY KEY, title VARCHAR(200));\n";
    const result = rune_reverse(sql.ptr, sql.len, "dialect=pg templates", 20);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_reverse invalid SQL" {
    const sql = "NOT VALID SQL STATEMENT";
    const result = rune_reverse(sql.ptr, sql.len, "", 0);
    // Invalid SQL may produce empty output or error — just verify no crash
    _ = result;
    @import("error.zig").rune_reset();
}

test "rune_reverse MySQL dialect" {
    const sql = "CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100)) ENGINE=InnoDB;\n";
    const result = rune_reverse(sql.ptr, sql.len, "dialect=mysql", 12);
    try std.testing.expect(result != null);
    if (result) |r| {
        const ss = std.mem.span(r);
        try std.testing.expect(ss.len > 0);
    }
    @import("error.zig").rune_reset();
}
