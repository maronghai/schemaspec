const std = @import("std");
const diag = @import("../semantic/diagnostic.zig");
const sql_parser = @import("../parser/sql_parser.zig");
const reverse_codegen = @import("../reverse/codegen.zig");
const codegen = @import("../codegen/codegen.zig");
const io_mod = @import("../io.zig");

// ─── Reverse Pipeline: SQL → .ss ─────────────────────────────

/// Auto-detect SQL dialect from content patterns using weighted scoring.
/// Each pattern match adds weight to the corresponding dialect score.
/// Highest score wins; ties default to MySQL.
pub fn detectSqlDialect(sql: []const u8) codegen.Dialect {
    var scores = [3]u8{ 0, 0, 0 }; // mysql, pg, sqlite

    // MySQL-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "ENGINE=") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "CHARACTER SET") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "DEFAULT CHARSET") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "AUTO_INCREMENT") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "UNSIGNED") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "FULLTEXT INDEX") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "COMMENT '") != null) scores[0] += 1;
    if (std.mem.indexOf(u8, sql, "ROW_FORMAT=") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "COLLATE=") != null) scores[0] += 1;
    if (std.mem.indexOf(u8, sql, "UNIQUE KEY") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "KEY `") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "ON UPDATE CURRENT_TIMESTAMP") != null) scores[0] += 1;

    // PostgreSQL-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS IDENTITY") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "COMMENT ON") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE EXTENSION") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "ENCODING=") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE TYPE") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "IF NOT EXISTS\n  (") != null) scores[1] += 1; // PG style serial
    if (std.mem.indexOf(u8, sql, "SERIAL") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "BIGSERIAL") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "bytea") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "boolean") != null) scores[1] += 1;
    if (std.mem.indexOf(u8, sql, "jsonb") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "timestamptz") != null) scores[1] += 3;

    // SQLite-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "AUTOINCREMENT") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "INTEGER PRIMARY KEY") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "WITHOUT ROWID") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "STRICT") != null) scores[2] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE TABLE \"") != null) scores[2] += 1;
    if (std.mem.indexOf(u8, sql, "ON CONFLICT") != null) scores[2] += 1;

    // Determine winner (ties → MySQL)
    var best: usize = 0;
    for (scores, 0..) |s, i| {
        if (s > scores[best]) best = i;
    }

    return switch (best) {
        1 => .pg,
        2 => .sqlite,
        else => .mysql,
    };
}

pub fn handleReverse(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, input_name: []const u8, output_path: ?[]const u8, with_templates: bool, dialect: codegen.Dialect, trace: bool) !void {
    // Auto-detect dialect from SQL content when not explicitly specified
    const sql_dialect: sql_parser.Dialect = if (dialect == .mysql) detectSqlDialect(file_data) else dialect;

    // Use DiagnosticCollector for consistent error handling with forward pipeline
    var diagnostics = try diag.DiagnosticCollector.init(alloc);

    var sp_parser = try sql_parser.SqlParser.init(alloc, file_data, sql_dialect);
    const result = sp_parser.parse() catch |err| {
        const lc = sp_parser.lineColAt(sp_parser.pos);
        const src_line = sp_parser.getSourceLine(lc.line);
        diagnostics.record(.{
            .severity = .@"error",
            .line_no = lc.line,
            .col = lc.col,
            .file = input_name,
            .message = "SQL syntax error",
            .source_line = src_line,
            .actual = @errorName(err),
        });
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.SqlParseError;
    };
    const schema = result.schema;

    for (result.diagnostics) |d| {
        diagnostics.record(.{
            .severity = d.severity,
            .line_no = d.line_no,
            .col = d.col,
            .file = input_name,
            .message = d.message,
            .source_line = d.source_line,
        });
    }

    if (diagnostics.hasErrors()) {
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.ReverseDiagnosticsError;
    }

    if (schema.tables.len == 0) {
        std.debug.print("warning: no tables found in SQL input\n", .{});
    }

    if (trace) {
        traceSqlSchema(schema);
    }

    var rcg = reverse_codegen.ReverseCodegen.init(alloc, sql_dialect);
    const ss_text = if (with_templates)
        try rcg.generateWithTemplates(schema)
    else
        try rcg.generate(schema);

    try io_mod.writeOutput(io, ss_text, output_path);
}

// ─── Trace Helper ──────────────────────────────────────────────

fn traceSqlSchema(schema: sql_parser.SqlSchema) void {
    std.debug.print("=== [Reverse: SqlSchema] ===\n\n", .{});
    std.debug.print("Schema: {?s}\n", .{schema.name});
    std.debug.print("Tables ({d}):\n", .{schema.tables.len});
    for (schema.tables) |table| {
        std.debug.print("  # {s} ({d} columns, {d} indexes, {d} fks)\n", .{ table.name, table.columns.len, table.indexes.len, table.foreign_keys.len });
        for (table.columns) |col| {
            std.debug.print("    {s: <24} {s}", .{ col.name, col.type_sql });
            if (col.primary_key) std.debug.print(" PK", .{});
            if (col.auto_increment) std.debug.print(" AI", .{});
            if (col.nullable) std.debug.print(" NULL", .{});
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n", .{});
}

// ─── Unit Tests ─────────────────────────────────────────────

const testing = std.testing;

test "detectSqlDialect: MySQL patterns" {
    const sql =
        \\CREATE TABLE `user` (
        \\  `id` int NOT NULL AUTO_INCREMENT,
        \\  PRIMARY KEY (`id`)
        \\) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detectSqlDialect(sql));
}

test "detectSqlDialect: PostgreSQL patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
        \\);
        \\COMMENT ON TABLE "user" IS 'User accounts';
    ;
    try testing.expectEqual(codegen.Dialect.pg, detectSqlDialect(sql));
}

test "detectSqlDialect: SQLite patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" INTEGER PRIMARY KEY AUTOINCREMENT
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detectSqlDialect(sql));
}

test "detectSqlDialect: SQLite STRICT" {
    const sql =
        \\CREATE TABLE "config" (
        \\  "key" TEXT NOT NULL,
        \\  "value" TEXT
        \\) STRICT;
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detectSqlDialect(sql));
}

test "detectSqlDialect: PostgreSQL CREATE EXTENSION" {
    const sql =
        \\CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        \\CREATE TABLE "items" (
        \\  "id" integer NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.pg, detectSqlDialect(sql));
}

test "detectSqlDialect: MySQL UNSIGNED and FULLTEXT" {
    const sql =
        \\CREATE TABLE `products` (
        \\  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
        \\  FULLTEXT INDEX `idx_search` (`name`)
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detectSqlDialect(sql));
}

test "detectSqlDialect: ambiguous defaults to MySQL" {
    const sql =
        \\CREATE TABLE items (
        \\  id int NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detectSqlDialect(sql));
}
