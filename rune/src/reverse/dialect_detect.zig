const std = @import("std");
const codegen = @import("../codegen/codegen.zig");

// ─── SQL Dialect Detection ─────────────────────────────────────
//
// Auto-detects SQL dialect from content patterns using weighted scoring.
// Each pattern match adds weight to the corresponding dialect score.
// Highest score wins; ties default to MySQL.
//
// Extracted from pipeline/reverse.zig in v0.7.1 for single-responsibility.

/// Auto-detect SQL dialect from content patterns using weighted scoring.
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
